use JSON::XS;
use LWP::Simple;

use strict;
use warnings;

my $sourcedir = `rpm --eval '%{_sourcedir}'`;
chomp $sourcedir;
my $specdir = `rpm --eval '%{_specdir}'`;
chomp $specdir;

my $package = shift
	or die 'Missing package argument';

# FIXME: Server returns... not quite JSON.
my $metadata_json = `npm view $package`;
$metadata_json =~ s/\b([^"':\s]+)(:\s+)/"$1"$2/gm;
$metadata_json =~ s/'/"/gm;
my $metadata = decode_json ($metadata_json);

my $date = `date +'%a %b %d %Y'`;
chomp $date;
my $user = $ENV{USER};
my $email = [split (/:/, `getent passwd $user`)]->[4];

open (SPEC, ">$specdir/nodejs-$metadata->{name}.spec")
	or die $!;

my $tarball = $sourcedir.[$metadata->{dist}{tarball} =~ /(\/[^\/]+)$/]->[0];
mirror ($metadata->{dist}{tarball}, $tarball);

my $dir = [`tar tzf $tarball` =~ /([^\/]+)/]->[0];
$dir =~ s/$metadata->{version}/%{version}/g;

my $source = $metadata->{dist}{tarball};
$source =~ s/$metadata->{version}/%{version}/g;

print SPEC <<EOF;
Name:           nodejs-$metadata->{name}
Version:        $metadata->{version}
Release:        1%{?dist}
Summary:        $metadata->{description}

Group:          Development/Libraries
License:        MIT
URL:            FIXME
Source0:        $source
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:  npm
Requires:       nodejs

BuildArch:      noarch

%description
$metadata->{description}


%prep
%setup -q -n $dir


%build


%install
rm -rf \$RPM_BUILD_ROOT
npm_config_root=\$RPM_BUILD_ROOT%{_prefix}/lib/node \\
npm_config_binroot=\$RPM_BUILD_ROOT%{_bindir} \\
npm_config_manroot=\$RPM_BUILD_ROOT%{_mandir} \\
npm install %{SOURCE0}


%clean
rm -rf \$RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_prefix}/lib/node/$metadata->{name}*
%{_prefix}/lib/node/.npm/$metadata->{name}*
%exclude %{_prefix}/lib/node/.npm/.cache
%doc LICENSE*


%changelog
* $date $user <$email> - $metadata->{version}-1
- Initial packaging
EOF

close SPEC;
