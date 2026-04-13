module Devise
  module Models
    module LdapMultidomainAuthenticatable
      extend ActiveSupport::Concern

      included do
        # Devise re-renders the sign-in resource with a password field on failure.
        # Provide a virtual attribute even when database_authenticatable is not used.
        attr_accessor :password
      end
    end
  end
end
