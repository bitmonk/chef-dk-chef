# Encoding: UTF-8
#
# Cookbook Name:: chef-dk
# Library:: provider_chef_dk
#
# Copyright 2014, Jonathan Hartman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'net/http'
require 'uri'
require 'chef/provider'
require 'chef/resource/package'
require 'chef/resource/remote_file'
require 'chef/util/file_edit'
require_relative 'chef_dk_helpers_metadata'
require_relative 'resource_chef_dk'

class Chef
  class Provider
    # A Chef provider for the Chef-DK packages
    #
    # @author Jonathan Hartman <j@p4nt5.com>
    class ChefDk < Provider
      PACKAGE_NAME ||= 'chefdk'
      METADATA_BASE ||= "https://www.opscode.com/chef/metadata-#{PACKAGE_NAME}"

      #
      # WhyRun is supported by this provider
      #
      # @return [TrueClass, FalseClass]
      #
      def whyrun_supported?
        true
      end

      #
      # Load and return the current resource
      #
      # @return [Chef::Resource::ChefDk]
      #
      def load_current_resource
        @current_resource ||= Resource::ChefDk.new(new_resource.name)
      end

      #
      # Download and install the ChefDk package
      #
      def action_install
        remote_file.run_action(:create)
        global_shell_init(:create).write_file if new_resource.global_shell_init
        package.run_action(:install)
        new_resource.installed = true
      end

      #
      # Uninstall the ChefDk package and delete the cached file
      #
      def action_remove
        global_shell_init(:delete).write_file if new_resource.global_shell_init
        package.run_action(:remove)
        remote_file.run_action(:delete)
        new_resource.installed = false
      end

      private

      #
      # The Package resource for the package
      #
      # @return [Chef::Resource::Package, Chef::Resource::DmgPackage]
      #
      def package
        @package ||= package_resource_class.new(download_path, run_context)
        @package.provider(package_provider_class) if package_provider_class
        tailor_package_resource_to_platform
        @package
      end

      #
      # Call any platform customization methods for the package resource
      #
      def tailor_package_resource_to_platform
        @package.version(new_resource.version)
      end

      #
      # The appropriate package resource class for this platform
      #
      # @return [Chef::Resource::Package]
      #
      def package_resource_class
        Chef::Resource::Package
      end

      #
      # A specified package provider class, if appropriate
      #
      # @return [NilClass]
      #
      def package_provider_class
        nil
      end

      #
      # The resource for the global shell init file
      #
      # @return [Chef::Util::FileEdit]
      #
      def global_shell_init(action = nil)
        matcher = /^eval "\$\(chef shell-init bash\)"$/
        line = 'eval "$(chef shell-init bash)"'
        @global_shell_init ||= Chef::Util::FileEdit.new(bashrc_file)
        case action
        when :create
          @global_shell_init.insert_line_if_no_match(matcher, line)
        when :delete
          @global_shell_init.search_file_delete_line(matcher)
        end
        @global_shell_init
      end

      #
      # The RemoteFile resource for the package
      #
      # @return [Chef::Resource::RemoteFile]
      #
      def remote_file
        @remote_file ||= Resource::RemoteFile.new(download_path, run_context)
        @remote_file.source(metadata.url)
        @remote_file.checksum(metadata.sha256)
        @remote_file
      end

      #
      # The filesystem path to download the package to
      #
      # @return [String]
      #
      def download_path
        ::File.join(Chef::Config[:file_cache_path], metadata.filename)
      end

      #
      # Get the package metadata
      #
      # @return [Hash]
      #
      def metadata
        @metadata ||= ::ChefDk::Helpers::Metadata.new(PACKAGE_NAME,
                                                      node,
                                                      new_resource)
      end

      # Some methods have to be provided by the sub-classes
      [:bashrc_file].each do |method|
        define_method(method, proc { fail(NotImplemented, method) })
      end

      # A custom exception class for unimplemented methods
      #
      # @author Jonathan Hartman <j@p4nt5.com>
      class NotImplemented < StandardError
        def initialize(method)
          super("Method `#{method}` has not been implemented")
        end
      end
    end
  end
end
