require 'json'
require 'rack'
require 'cypress_dev/configuration'
require 'cypress_dev/command_executor'

module CypressDev
  # Middleware to handle cypress commands and eval
  class Middleware
    def initialize(app, command_executor = CommandExecutor, file = ::File)
      @app = app
      @command_executor = command_executor
      @file = file
    end

    def call(env)
      request = Rack::Request.new(env)
      if request.path.start_with?('/__cypress__/command')
        configuration.tagged_logged { handle_command(request) }
      else
        @app.call(env)
      end
    end

    private

    def configuration
      CypressDev.configuration
    end

    def logger
      configuration.logger
    end

    Command = Struct.new(:name, :options, :cypress_folder) do
      # @return [Array<Cypress::Middleware::Command>]
      def self.from_body(body, configuration)
        if body.is_a?(Array)
          command_params = body
        else
          command_params = [body]
        end
        command_params.map do |params|
          new(params.fetch('name'), params['options'], configuration.cypress_folder)
        end
      end

      def file_path
        "#{cypress_folder}/app_commands/#{name}.rb"
      end
    end

    def handle_command(req)
      body = JSON.parse(req.body.read)
      logger.info "handle_command: #{body}"
      commands = Command.from_body(body, configuration)
      missing_command = commands.find {|command| !@file.exists?(command.file_path) }
      if missing_command.nil?
        results = commands.map { |command| @command_executor.load(command.file_path, command.options) }

        [201, {}, results]
      else
        [404, {}, ["could not find command file: #{missing_command.file_path}"]]
      end
    end
  end
end
