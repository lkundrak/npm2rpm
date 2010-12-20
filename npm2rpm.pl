#!/bin/env perl

=head1 NAME

npm2rpm - Generate RPM packages SPEC from node.js NPM metadata

=head1 SYNOPSIS

npm2rpm
[--specdir <specdir>]
[--sourcedir <sourcedir>]
[--user <user>]
[--email <email>]
[--date <date>]
[[--package] <package>]
[-h|--help] [-H|--man]

=head1 DESCRIPTION

The utility is designed to auto-generate skeleton of rpm package
from NPM metadata. The resulting package is intended to comply with
Fedora packaging guidelines.

npm2rpm will download the package metadata, determine the URL of
distribution tarball, download it and write a spec file called
nodejs-<package>.spec into your SPEC file directory.

=cut

use Getopt::Long;
use JSON::XS;
use LWP::Simple;
use Pod::Usage;

use strict;
use warnings;

# Defaults
my $sourcedir = `rpm --eval '%{_sourcedir}'`;
chomp $sourcedir;
my $specdir = `rpm --eval '%{_specdir}'`;
chomp $specdir;
my $date = `date +'%a %b %d %Y'`;
chomp $date;
my $user = $ENV{USER};
my $email = [split (/:/, `getent passwd $user`)]->[4];
my $package;

# Parse command line options
GetOptions (
	'h|help'	=> sub { pod2usage({-verbose => 1}); exit },
	'H|man'		=> sub { pod2usage({-verbose => 2}); exit },
	"specdir=s"	=> \$specdir,
	"sourcedir=s"	=> \$sourcedir,
	"user=s"	=> \$user,
	"email=s"	=> \$email,
	"date=s"	=> \$date,
	"package=s"	=> \$package,
) or die "Run $0 -h or $0 -H for details on usage";

$package = shift @ARGV if @ARGV and not $package;
die 'Missing package argument' unless $package;
die "Extra arguments: @ARGV" if @ARGV;

# Get details from central NPM repository
# FIXME: Server returns... not quite JSON.
my $metadata_json = `npm view $package`;
$metadata_json =~ s/\b([^"':\s]+)(:\s+)/"$1"$2/gm;
$metadata_json =~ s/'/"/gm;
my $metadata = decode_json ($metadata_json);
die 'Could not  read and parse package metadata'
	unless $metadata;

# Create the SPEC file
open (SPEC, ">$specdir/nodejs-$metadata->{name}.spec")
	or die "Could not write into SPEC file: $!";

# Pull the tarball
my $tarball = $sourcedir.[$metadata->{dist}{tarball} =~ /(\/[^\/]+)$/]->[0];
mirror ($metadata->{dist}{tarball}, $tarball) or die $!;
my $source = $metadata->{dist}{tarball};

# Find out the top-level directory from tarball
# The upstreams often use very weird ones
my $dir = [`tar tzf $tarball` =~ /([^\/]+)/]->[0];

# Use macros wherever possible
$source =~ s/$metadata->{version}/%{version}/g;
$source =~ s/$metadata->{name}/%{npmname}/g;
$dir =~ s/$metadata->{version}/%{version}/g;
$dir =~ s/$metadata->{name}/%{npmname}/g;

# Build and runtime dependencies
my @dependencies;
foreach my $name (keys %{$metadata->{dependencies}}) {
	my $version = $metadata->{dependencies}{$name};
	$version =~ s/([>=<]+\s*)/$1 /;
	push @dependencies, "BuildRequires:  nodejs-$name $version";
	push @dependencies, "Requires:       nodejs-$name $version";
	@dependencies = sort @dependencies;
}
@dependencies = ('', @dependencies, '') if @dependencies;

# Keep track of runnable scripts (that go into /usr/bin)
my @bininst;
my @binfiles;
for my $bin (map { $_, "$_@%{version}" } keys %{$metadata->{bin}}) {
	push @bininst, "install -p usr/bin/$bin \$RPM_BUILD_ROOT%{_bindir}";
	push @binfiles, "%{_bindir}/$bin";
}
@bininst = ('', 'mkdir -p $RPM_BUILD_ROOT%{_bindir}', @bininst) if @bininst;
@binfiles = (@binfiles, '') if @binfiles;

# Fill in the template
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

BuildRequires:  nodejs-npm
Requires:       nodejs-npm
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

=head1 OPTIONS

=over

=item B<--specdir> B<< <specdir> >>

Where to write the resulting SPEC file to.
Defaults to B<%_specdir> RPM macro, which is usually
~/rpmbuild/SPECS (or /usr/src/redhat/SPECS on ancient
RPM versions).

=item B<--sourcedir> B<< <sourcedir> >>

Where to download the upstream distribution tarball to.
Defaults to B<%_sourcedir> RPM macro, which is usually
~/rpmbuild/SOURCES (or /usr/src/redhat/SOURCES on ancient
RPM versions).

=item B<--date> B<< <date> >>

Date to use for initial changelog entry (e.g. Mon Dec 20 2010).
Defaults to output of C<date +'%a %b %d %Y'>.

=item B<--user> B<< <user> >>

Name (in "Firstname Lastname") format to use for initial
changelog entry. Defaults to your account's real name.

=item B<--email> B<< <email> >>

E-mail address to use in initial changelog entry.
Defaults to your login.

=item [B<--package>] B<< <package> >>

The NPM package name to act upon. Mandatory.

=item B<-h>, B<--help>

Prints and error message and exits

=item B<-H>, B<--manual>

Show the complete manual page and exit.

=back

=head1 BUGS

The resulting package is ugly as hell -- due the way NPM currently
works the whole npm tree has to be copied for unprivileged build,
which is inefficient.

NPM packages sometimes lack pieces of metadata this tool uses;
you may see "uninitialized" warnings from perl, as well as empty
or "FIXME" tags in the resulting SPEC file.

While for simple packages and good configuration the package can
be used as it is, the weirder package is the higher are chances
you'll have to hand-edit it.

=head1 EXAMPLES

=over 4

=item C<npm2rpm jsdom>

Well, nothing particularly sophisticated.

=back

=head1 SEE ALSO

L<cpanspec>, L<https://fedoraproject.org/wiki/User:Lkundrak/NodeJS>


=cut
