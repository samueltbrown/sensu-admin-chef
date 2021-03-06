#
# Cookbook Name:: sensu-admin
# Recipe:: default
#
# Copyright 2012, Sonian Inc.
# Copyright 2012, Needle Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Note: This default install uses sqlite, which uses a file on the HD, if you lose this file your audit, downtime and user audits/logs will be gone.
# If this is important to you - BACK IT UP, or use a SQL DB thats already backed up for you.
#

package "git"
package "sqlite"
package "sqlite-devel"

# bundle install fails unless the mysql c libraries are available
include_recipe "mysql::ruby"

user node.sensu.admin.user do
  home node.sensu.admin.base_path
  system true
end

gem_package "unicorn"
gem_package "bundler"
gem_package "rake" do
  version "0.9.2.2"
end

directory node.sensu.admin.base_path do
  owner node.sensu.admin.user
  group node.sensu.admin.user
  mode '0755'
  recursive true
end

# Otherwise chef is making the child directories owned by root (under recursive true)
%w{ website
    website/shared
    website/shared/config
    website/shared/log
    website/shared/db
    website/shared/bundle
    website/shared/pids }.each do |dir|
  directory "#{node.sensu.admin.base_path}/#{dir}" do
    owner node.sensu.admin.user
    group node.sensu.admin.user
    mode '0755'
    recursive true
  end
end

template "#{node.sensu.admin.base_path}/sensu-admin-unicorn.rb" do
  user node.sensu.admin.user
  group node.sensu.admin.user
  source "sensu-admin-unicorn.rb.erb"
  variables(:workers => node.cpu.total.to_i + 1,
            :base_path => node.sensu.admin.base_path,
            :backend_port => node.sensu.admin.backend_port)
end

template "/etc/init.d/sensu-admin" do
  source "unicorn.init.erb"
  owner "root"
  group "root"
  mode "0755"
  variables(:base_path => node.sensu.admin.base_path)
end

deploy_revision "sensu-admin" do
  action :deploy
  repository node.sensu.admin.repo
  revision node.sensu.admin.release
  user node.sensu.admin.user
  group node.sensu.admin.group
  environment "RAILS_ENV" => "production"
  deploy_to "#{node.sensu.admin.base_path}/website"
  create_dirs_before_symlink %w{tmp tmp/cache}
  purge_before_symlink %w{log}
  symlink_before_migrate "db/production.sqlite3" => "db/production.sqlite3"
  symlinks "log"=>"log"
  shallow_clone false
  enable_submodules true
  before_migrate do
    execute "bundle install --path #{node.sensu.admin.base_path}/website/shared/bundle" do
      user "root"
      cwd release_path
    end
  end
  before_symlink do
    execute "rake db:create" do
      user node.sensu.admin.user
      cwd release_path
      not_if "test -f #{release_path}/db/production.sqlite3"
    end
    file "#{release_path}/db/production.sqlite3" do
      user node.sensu.admin.user
      mode "0600"
      only_if "test -f #{release_path}/db/production.sqlite3"
    end
  end
  before_restart do
    execute "bundle exec whenever --update-crontab" do
      cwd ::File.join(node.sensu.admin.base_path,'website','current')
      user node.sensu.admin.user
    end
  end
  migrate true
  migration_command "bundle exec rake db:migrate --trace >/tmp/migration.log 2>&1 && bundle exec rake assets:precompile && bundle exec rake db:seed"
end

service "sensu-admin" do
  supports :status => true, :restart => true, :reload => true
  action [ :enable, :start ]
end
