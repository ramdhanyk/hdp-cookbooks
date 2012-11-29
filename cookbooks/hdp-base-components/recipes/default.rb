#
# Cookbook Name:: hdp-base-components
# Recipe:: default
#
# Copyright 2012, chalupaul
#
# All rights reserved - Do Not Redistribute
#

# This cookbook performs global settings changes and
# necessary package install. Anything specific to hadoop
# roles will be found in those recipes

# System tweaks to increase performance and reliability

# Increase Filesystem limits.
# Strips out any open files limits and replaces it with a big number
configmunge "increase open files limit" do
  config_file "/etc/security/limits.conf"
  filter /^[^#].*nofile/ 
  appended_configs ["*  hard  nofile  #{node[:hortonworks_hdp][:nofiles]}\n"]
end

# Ensure SELinux is disabled
configmunge "disable selinux" do
  config_file "/etc/sysconfig/selinux"
  filter /^SELINUX=/
  appended_configs ["SELINUX=disabled\n"]
end
execute "disable selinux - running" do
  command "setenforce 0"
  returns [0, 1]
end

# HDP requires a little more than 2x swap to vmm size (we use 
# system memory to be safe. This swap doesn't
# get used, just reserved during spawning.

total_memory = Integer(node[:memory][:total].sub("kB", ''))
total_swap = Integer(node[:memory][:swap][:total].sub("kB", ''))
swapsize_raw = total_memory * 2.25 - total_swap
$swapsize = ((swapsize_raw * 2).round / 2.0).floor

swapfile "create swapfile" do
  swapfile_location node[:hortonworks_hdp][:swapfile_location]
  swapsize $swapsize
end



# Package Installation

# These have to come first to bootstrap the rest
%w'wget java-1.6.0-openjdk-devel'.each do | pack |
  package pack do
    action :install
  end
end

execute "install hdp repo package" do
  command "rpm -Uvh http://public-repo-1.hortonworks.com/HDP-1.1.0.15/repos/centos6/hdp-release-1.1.0.15-1.el6.noarch.rpm"
  not_if do
    ::File.exists?("/etc/yum.repos.d/hdp.repo")
  end
end

# This package is made available by the hdp package above
package "epel-release" do
  action :install
end

%w'hadoop 
hadoop-native 
hadoop-pipes 
hadoop-libhdfs 
snappy 
snappy-devel 
openssl 
hadoop-lzo 
lzo 
lzo-devel 
hadoop-lzo-native'.each do | pack |
  package pack do
    action :install
  end
end

%w'snappy snappy-devel'.each do | pack |
  yum_package pack do
    arch "i686"
    action :install
  end
end

execute "symlink snappy in" do
  command "ln -sf /usr/lib64/libsnappy.so /usr/lib/hadoop/lib/native/Linux-amd64-64/"
  not_if do
    ::File.exist?("/usr/lib/hadoop/lib/native/Linux-amd64-64/libsnappy.so")
  end
end

# Create cache directory
directory "/var/lib/hadoop/cache" do
  owner "root"
  group "root"
  mode "1777"
  recursive true
  action :create
end

directory "/etc/hadoop/conf.chef" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

execute "alternatives configured confdir" do
  command "alternatives --install /etc/hadoop/conf hadoop-conf /etc/hadoop/conf.chef 90"
  not_if do
    ::File.readlink("/etc/alternatives/hadoop-conf") == "/etc/hadoop/conf.chef"
  end
end


# Install base configuration (will be the same on every install)

%w'capacity-scheduler.xml 
configuration.xsl 
fair-scheduler.xml 
hadoop-env.sh 
hadoop-policy.xml 
log4j.properties 
mapred-queue-acls.xml 
hadoop-metrics.properties
hadoop-metrics2.properties
taskcontroller.cfg'.each do | f |
  template "/etc/hadoop/conf.chef/#{f}" do
    source "#{f}.erb"
    mode 0755
    user "root"
    group "root"
    only_if do
      not ::File.exists?("/etc/hadoop/conf.chef/#{f}") || node[:hortonworks_hdp][:manage_all_config_files] == true
    end
  end
end

template "/etc/hadoop/conf.chef/core-site.xml" do
  source "core-site.xml.erb"
  mode 0755
  user "root"
  group "root"
  variables({
              :namenode_ip => node[:hortonworks_hdp][:master_node_ip],
              :namenode_port => node[:hortonworks_hdp][:namenode][:port]
            })
end

template "/etc/hadoop/conf.chef/hdfs-site.xml" do
  source "hdfs-site.xml.erb"
  mode 0755
  user "root"
  group "root"
  variables({
              :safemode_min_datanodes => node[:hortonworks_hdp][:namenode][:safemode_min_datanodes],
              :num_dfs_replicas => node[:hortonworks_hdp][:namenode][:num_dfs_replicas]
            })
end

template "/etc/hadoop/conf.chef/mapred-site.xml" do
  source "mapred-site.xml.erb"
  owner "root"
  group "root"
  mode 0755
  variables({
              :jobtracker_ip => node[:hortonworks_hdp][:master_node_ip],
              :jobtracker_port => node[:hortonworks_hdp][:jobtracker][:port]
            })
end
