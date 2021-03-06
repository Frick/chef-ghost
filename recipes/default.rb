### Setup NodeJS and NPM
node.set[:nodejs][:version] = "0.10.21"
node.set[:nodejs][:checksum] = "7c125bf22c1756064f2a68310d4822f77c8134ce178b2faa6155671a8124140d"
node.set[:nodejs][:checksum_linux_x86] = "c0ed641961a5c5a4602b1316c3d3ed12b3ac330cc18abf3fb980f0b897b5b96b"
node.set[:nodejs][:checksum_linux_x64] = "2791efef0a1e9a9231b937e55e5b783146e23291bca59a65092f8340eb7c87c8"

include_recipe "nodejs::install_from_binary"

### Setup User and Install Directory
include_recipe "ghost::user"

directory node[:ghost][:install_path] do
  owner node[:ghost][:user]
  group node[:ghost][:user]
  mode "0755"
  recursive true
  action :create
end

### Download and Extract Ghost Archive
include_recipe "ark"

ark 'ghost' do
  url node[:ghost][:src_url]
  path node[:ghost][:install_path]
  owner node[:ghost][:user]
  strip_leading_dir false
  action :put
end

extract_dir = ::File.join(node[:ghost][:install_path], "ghost")

### Work-around for bug in ark cookbook
bash "unzip_ghost" do
  cwd Chef::Config[:file_cache_path]
  code "unzip -q -u -o #{Chef::Config[:file_cache_path]}/ghost.zip -d #{extract_dir}"
  not_if do
    File.exists?("#{extract_dir}/config.js")
  end
end

### Install Dependencies
bash "install_ghost" do
  cwd extract_dir 
  code "npm install --production"
end

bash "install_mysql_npm" do
  cwd extract_dir
  code "npm install mysql" 
end

### Load Secrets from Databag
if node[:ghost][:databag]
  databag = Chef::EncryptedDataBagItem.load(node[:ghost][:databag], node[:ghost][:databag_item])
  node.set_unless[:ghost][:mail_password] = databag['ghost']['mail_password'] rescue nil
  node.set_unless[:ghost][:db_password] = databag[:ghost]['db_password'] rescue nil
end

### Create Config
template ::File.join(extract_dir, "config.js") do
  source "config.js.erb"
  owner node[:ghost][:user]
  group node[:ghost][:user]
  mode "0660"
  variables(
    :url		=> node[:ghost][:domain],
    :mail_transport     => node[:ghost][:mail_transport].downcase,
    :mail_user  	=> node[:ghost][:mail_user],
    :mail_password 	=> node[:ghost][:mail_password],
    :db_host		=> node[:ghost][:db_host],
    :db_user		=> node[:ghost][:db_user],
    :db_password	=> node[:ghost][:db_password],
    :db_name		=> node[:ghost][:db_name]
  )
end

### Install Themes
node[:ghost][:themes].each do |name,source_url|
  ghost_theme name do
    source source_url
  end
end

### Set File Ownership
bash "set_ownership" do
  cwd node[:ghost][:install_path]
  code "chown -R #{node[:ghost][:user]}:#{node[:ghost][:user]} #{node[:ghost][:install_path]}"
end

### Create Service 
case node[:platform]
when "ubuntu"
  if node["platform_version"].to_f >= 9.10
    template "/etc/init/ghost.conf" do
      source "ghost.conf.erb"
      mode "0644"
      variables(
        :user		=> node[:ghost][:user],
        :dir		=> extract_dir 
      )
    end
  end
end

service "ghost" do
  case node["platform"]
  when "ubuntu"
    if node["platform_version"].to_f >= 9.10
      provider Chef::Provider::Service::Upstart
    end
  end
  action [ :enable, :start ]
end
