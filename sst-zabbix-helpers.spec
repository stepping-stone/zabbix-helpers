Name:    sst-zabbix-helpers
Version: 2.5.0
Release: 1%{?dist}
Summary: stepping stone Zabbix helper scripts
URL:     https://github.com/stepping-stone/zabbix-helpers
License: none
BuildArch: noarch
Vendor: stepping stone GmbH
Requires: zabbix-agent

Source0: https://github.com/stepping-stone/zabbix-helpers/archive/v%{version}.tar.gz

%description
Various helper scripts for usage with Zabbix monitoring.

%prep
%setup -n zabbix-helpers-%{version}

%build

%install
mkdir -p %{buildroot}%{_sysconfdir}/sudoers.d/
mkdir -p %{buildroot}%{_sysconfdir}/zabbix-helpers/get-status.d/
mkdir -p %{buildroot}%{_sysconfdir}/zabbix/zabbix_agentd.d
mkdir -p %{buildroot}%{_libexecdir}/zabbix-helpers/
mkdir -p %{buildroot}%{_datadir}/zabbix-helpers

install -m 644 etc/sudoers.d/* %{buildroot}%{_sysconfdir}/sudoers.d/
install -m 644 etc/zabbix-helpers/*.conf %{buildroot}%{_sysconfdir}/zabbix-helpers/
install -m 644 etc/zabbix-helpers/get-status.d/* %{buildroot}%{_sysconfdir}/zabbix-helpers/get-status.d/
install -m 644 etc/zabbix/zabbix_agentd.d/* %{buildroot}%{_sysconfdir}/zabbix/zabbix_agentd.d/
install -m 755 usr/libexec/zabbix-helpers/* %{buildroot}%{_libexecdir}/zabbix-helpers/
install -m 644 usr/share/zabbix-helpers/* %{buildroot}%{_datadir}/zabbix-helpers

%files
%{_sysconfdir}/sudoers.d/cmnd_alias-du
%{_sysconfdir}/sudoers.d/cmnd_alias-gitlab-ctl
%{_sysconfdir}/sudoers.d/cmnd_alias-letsencrypt                 
%{_sysconfdir}/sudoers.d/cmnd_alias-lvm                         
%{_sysconfdir}/sudoers.d/cmnd_alias-mdadm                       
%{_sysconfdir}/sudoers.d/cmnd_alias-open-file-descriptors       
%{_sysconfdir}/sudoers.d/user-zabbix_du
%{_sysconfdir}/sudoers.d/user-zabbix_gitlab-ctl
%{_sysconfdir}/sudoers.d/user-zabbix_letsencrypt                
%{_sysconfdir}/sudoers.d/user-zabbix_lvm                        
%{_sysconfdir}/sudoers.d/user-zabbix_mdadm                      
%{_sysconfdir}/sudoers.d/user-zabbix_open-file-descriptors      
%config(noreplace) %{_sysconfdir}/zabbix-helpers/*
%{_sysconfdir}/zabbix/zabbix_agentd.d/sst.*
%{_libexecdir}/zabbix-helpers/
%{_datadir}/zabbix-helpers/

%clean
rm -rf %{buildroot}
