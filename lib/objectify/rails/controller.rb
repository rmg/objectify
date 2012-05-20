require "objectify/resolver_locator"
require "objectify/executor"
require "objectify/policy_chain_executor"
require "objectify/instrumentation"

module Objectify
  module Rails
    module ControllerHelpers
      private
        def objectify
          ::Rails.application.objectify
        end

        def injector
          objectify.injector
        end

        def request_resolver
          klass = Objectify::NamedValueResolverLocator
          @request_resolver ||= klass.new.tap do |resolver|
            resolver.add(:controller, self)
            resolver.add(:params, params)
            resolver.add(:session, session)
            resolver.add(:cookies, cookies)
            resolver.add(:request, request)
            resolver.add(:response, response)
            resolver.add(:flash, flash)
          end
        end
        
        def executor
          objectify.executor
        end

        def policy_chain_executor
          @policy_chain_executor ||= Objectify::PolicyChainExecutor.new(executor, objectify)
        end

        def action
          @action ||= if params[:objectify]
            route = Objectify::Route.new(params[:objectify][:resource].to_sym, params[:action].to_sym)
            objectify.action(route)
          else
            route = Objectify::Route.new(params[:controller].to_sym,
                                         params[:action].to_sym)
            objectify.legacy_action(route)
          end
        end

        def execute_policy_chain
          policy_chain_executor.call(action)
        end

        def objectify_around_filter
          objectify.resolver_locator.context(request_resolver)
          yield
          objectify.resolver_locator.clear_context
        end

        def execute_objectify_action
          service_result = executor.call(action.service, :service)
          request_resolver.add(:service_result, service_result)

          executor.call(action.responder, :responder)
        end
    end

    module LegacyControllerBehaviour
      include ControllerHelpers
      include Instrumentation

      def method_missing(name, *args, &block)
        instrument("start_processing.objectify", :route => route)

        execute_objectify_action
      end
    end

    module ControllerBehaviour
      include ControllerHelpers
      include Instrumentation

      def method_missing(name, *args, &block)
        instrument("start_processing.objectify", :route => route)

        if execute_policy_chain
          execute_objectify_action
        end
      end
    end

    class ObjectifyController < ActionController::Base
      include ControllerBehaviour
    end
  end
end
