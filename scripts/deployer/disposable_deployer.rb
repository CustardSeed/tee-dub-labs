require_relative 'talks_to_heroku'
require_relative 'deployer'
require_relative 'creates_uuids'
require_relative 'documents_actions'

module Deployer
  class DisposableDeployer
    include TalksToHeroku
    include DocumentsActions

    def go
      source_secrets
      do_deploy
    rescue 
      cleanup_after_failure
      raise
    ensure
      cleanup
    end

    private

    def do_deploy
      do_action('creating app'){ create_app }
      puts "created http://#{@app_name}.herokuapp.com"

      deploy_app

    end

    def create_app
      app_name = "disposable-#{deploy_uuid}"[0,30]
      heroku.post_app( name: app_name )
      @app_name = app_name
    end

    def deploy_app
      Deployer.new(@app_name,deploy_uuid).deploy
    end

    def cleanup
      # nothing to be done for now
    end

    def cleanup_after_failure
      destroy_app
    end

    def destroy_app
      heroku.delete_app( @app_name ) if @app_name
    end

    def deploy_uuid
      @deploy_uuid ||= CreatesUUIDs.generate_lowercase_uuid
    end
  end
end
