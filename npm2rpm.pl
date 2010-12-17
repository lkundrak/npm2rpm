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
mirror ($metadata->{dist}{tarball}, $tarball) or die $!;

my $dir = [`tar tzf $tarball` =~ /([^\/]+)/]->[0];
$dir =~ s/$metadata->{version}/%{version}/g;
$dir =~ s/$metadata->{name}/%{npmname}/g;

my $source = $metadata->{dist}{tarball};
$source =~ s/$metadata->{version}/%{version}/g;
$source =~ s/$metadata->{name}/%{npmname}/g;

my @dependencies;
foreach my $name (keys %{$metadata->{dependencies}}) {
	my $version = $metadata->{dependencies}{$name};
	$version =~ s/([>=<]+\s*)/$1 /;
	push @dependencies, "BuildRequires:  nodejs-$name $version";
	push @dependencies, "Requires:       nodejs-$name $version";
	@dependencies = sort @dependencies;
}
@dependencies = ('', @dependencies, '') if @dependencies;

my @bininst;
my @binfiles;
for my $bin (map { $_, "$_@%{version}" } keys %{$metadata->{bin}}) {
	push @bininst, "install -p usr/bin/$bin \$RPM_BUILD_ROOT%{_bindir}";
	push @binfiles, "%{_bindir}/$bin";
}
@bininst = ('', 'mkdir -p $RPM_BUILD_ROOT%{_bindir}', @bininst) if @bininst;
@binfiles = (@binfiles, '') if @binfiles;

print SPEC <<EOF;
%global npmname $metadata->{name}

Name:           nodejs-%{npmname}
Version:        $metadata->{version}
Release:        1%{?dist}
Summary:        $metadata->{description}

Group:          Development/Libraries
License:        $metadata->{licenses}{type}
URL:            FIXME
Source0:        $source
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

BuildRequires:  npm
Requires:       nodejs
EOF
print SPEC join "\n", @dependencies;
print SPEC <<EOF;

BuildArch:      noarch

%description
$metadata->{description}


%prep
%setup -q -n $dir


%build
mkdir -p .%{_prefix}/lib/node/.npm
cp -a %{_prefix}/lib/node/.npm/* \\
	.%{_prefix}/lib/node/.npm

npm_config_root=.%{_prefix}/lib/node \\
npm_config_binroot=.%{_bindir} \\
npm_config_manroot=.%{_mandir} \\
npm install %{SOURCE0}


%install
rm -rf \$RPM_BUILD_ROOT

mkdir -p \$RPM_BUILD_ROOT%{_prefix}/lib/node{,/.npm}
cp -a \$PWD%{_prefix}/lib/node/%{npmname}{,@%{version}} \\
	\$RPM_BUILD_ROOT%{_prefix}/lib/node
cp -a \$PWD%{_prefix}/lib/node/.npm/%{npmname} \\
	\$RPM_BUILD_ROOT%{_prefix}/lib/node/.npm
EOF
print SPEC join "\n", @bininst;
print SPEC <<EOF;


%clean
rm -rf \$RPM_BUILD_ROOT


%files
%defattr(-,root,root,-)
%{_prefix}/lib/node/%{npmname}
%{_prefix}/lib/node/%{npmname}@%{version}
%{_prefix}/lib/node/.npm/%{npmname}
EOF
print SPEC join "\n", @binfiles;
print SPEC <<EOF;
%doc LICENSE*


%changelog
* $date $user <$email> - $metadata->{version}-1
- Initial packaging
EOF

close SPEC;
