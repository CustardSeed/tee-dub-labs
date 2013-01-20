require 'heroku-api'
require 'pathname'
require 'tmpdir'

require 'pry'

def source_secrets
  secrets_file = File.expand_path( '../../.secrets', __FILE__ )
  return unless File.exists?(secrets_file)

  File.readlines(secrets_file).each do |line|
    (key,value) = line.split("=")
    key.sub!(/^export /,'')
    ENV[key] = value
  end
  nil
end

class DisposableAppDeleter
  def self.delete_all
    new.delete_all_apps
  end

  def delete_all_apps
    apps = heroku.get_apps.body.map{ |h| h['name'] }
    disposable_apps = apps.select{ |x| x.start_with?( 'disposable' ) }
    disposable_apps.each do |app|
      puts "deleting #{app}"
      heroku.delete_app app
    end
  end

  private
  
  def heroku
    @heroku ||= Heroku::API.new()
  end
end

class DisposableDeployer

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
    prep_temp_dir

    connect_to_heroku

    perform('creating app'){ create_app }
    puts "created http://#{@app_name}.herokuapp.com"

    setup_ssh_key
    push_head_to_app

  end

  def prep_temp_dir
    @tmpdir = Pathname.new( Dir.tmpdir ).join('heroku-deployer').join(deploy_uuid)
    @tmpdir.mkpath
  end

  def remove_temp_dir
    @tmpdir.rmtree
  end

  def connect_to_heroku
    @heroku = Heroku::API.new()
  end

  def create_app
    app_name = "disposable-#{deploy_uuid}"[0,30]
    @heroku.post_app( name: app_name )
    @app_name = app_name
  end

  def setup_ssh_key
    perform( 'creating ssh key' ){ create_ssh_key }
    perform( 'adding ssh key' ){ add_ssh_key }
  end

  def create_ssh_key
    `ssh-keygen -t rsa -N "" -C #{ssh_key_name} -f #{ssh_key_path}`
  end

  def ssh_key_path
    @tmpdir.join('id_rsa')
  end

  def ssh_key_name
    "deployer-#{deploy_uuid}"
  end

  def public_ssh_key
    ssh_key_path.sub_ext('.pub').read
  end

  def add_ssh_key
    @heroku.post_key(public_ssh_key)
  end
  
  def remove_ssh_key
    @heroku.delete_key(ssh_key_name)
  end

  def push_head_to_app
    setup_custom_git_ssh
    push_git
  end

  def setup_custom_git_ssh
   custom_git_ssh_path.open('w') do |f|
     f.write <<-EOF
       #!/bin/sh
       exec ssh -i #{ssh_key_path.expand_path} -- "$@"
     EOF
   end
   custom_git_ssh_path.chmod( 0740 )
  end

  def push_git
    puts `echo GIT_SSH=#{custom_git_ssh_path} git push git@heroku.com:#{@app_name}.git HEAD`
  end

  def custom_git_ssh_path
    @tmpdir.join('git-ssh')
  end

  def cleanup_after_failure
    destroy_app
  end

  def cleanup
    perform( 'removing ssh key' ){ remove_ssh_key }
    perform( 'removing temp dir' ){ remove_temp_dir }
  end

  def destroy_app
    @heroku.delete_app( @app_name ) if @app_name
  end

  def deploy_uuid
    @deploy_uuid ||= `uuidgen`.chomp.downcase
  end

  def perform(description)
    print "  " + description + " ..."
    yield
    puts " DONE"
  end
end

if __FILE__ == $0
  source_secrets
  DisposableDeployer.new.go
end
