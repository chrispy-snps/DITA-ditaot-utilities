#!/usr/bin/perl
use v5.16;
use warnings;
use strict;
use File::Basename;
use File::Spec;
use Getopt::Long 'HelpMessage';


# process command-line arguments
my $dita;
my $verbose;
GetOptions(
  'dita=s'     => \$dita,
  'verbose'    => \$verbose,
  'help'       => sub { HelpMessage(0) }
  ) or HelpMessage(1);

# if DITA-OT is not specified, look for 'dita' in the current search path
if (!defined($dita)) {
 $dita = (`which dita` =~ s!\R$!!r);  # try to get a default
 die "cannot find 'dita' in search path (use --dita to specify DITA-OT location)" if $dita eq '';
}

# resolve where the DITA-OT directory is
$dita = File::Spec->rel2abs($dita);  # get absolute path (can be <DITA-OT> or <DITA-OT>/bin/dita)
my $ditaot_dir = ($dita =~ s!\/(bin/.*)?$!!rs) or die "could not get DITA-OT root directory";  # remove trailing slash, 'bin/*'
die "could not find '$ditaot_dir'" if !-d $ditaot_dir;
my $catalog_file = "$ditaot_dir/catalog-dita.xml";
die "could not find '$catalog_file'" if !-f $catalog_file;
say "Using the DITA-OT installation at '$ditaot_dir'." if $verbose;
die "could not find 'xmlcatalog' in search path" if system('which xmlcatalog > /dev/null') != 0;

# make sure all input files/directories exist
my @files_dirs_to_process = @ARGV;
if (my @not_found = grep {!-e} @files_dirs_to_process) {
 say STDERR "Error: Could not find the following:";
 say STDERR "  $_" for @not_found;
 exit 1;
}

# loop through each command-line file or directory
my @files_to_process = ();
foreach my $file_dir (@files_dirs_to_process) {
 my $is_file = (-f $file_dir);  # is this a file?
 my $src_dir = $is_file ? dirname($file_dir) : $file_dir;

 # filter files/directories for correct extension (.dita*), expand directories
 push @files_to_process, ($is_file ?
  $file_dir :
  (split(/\n/, `find "$file_dir" \\( -iname \\*.dita -o -iname \\*.ditamap \\)`)));
}

# group files by their URI
my %files_for_uri = ();
foreach my $file (@files_to_process) {
 my $uri = get_uri_for_file($file) or do {
  say STDERR "Error: Could not obtain URI for '$file'.";
  next;
 };
 push @{$files_for_uri{$uri}}, $file;
}

# validate files for each URI group
foreach my $uri (sort keys %files_for_uri) {
 my $schema_file = get_schema_file_for_uri($uri) or next;
 my @files_for_uri = @{$files_for_uri{$uri}};
 say sprintf("Validating %d files against '%s' (%s)...", scalar(@files_for_uri), $uri, $schema_file) if $verbose;

 while (@files_for_uri) {
  my @args = ('jing', '-C', "${ditaot_dir}/catalog-dita.xml", $schema_file);
  my $length = length("@args");

  while (@files_for_uri && (my $newlength = ($length + length($files_for_uri[0]))) < 127*1024) {
   push @args, shift @files_for_uri;
   $length = $newlength;
  }
  system(@args);
 }
}




####
## HELPER SUBROUTINES
##

# read in the file, extract and return the RelaxNG URI
sub get_uri_for_file {
 my $file = shift;
 open(FILE, "<$file") or do {
  say STDERR "Error: Could not open '$file': $!";
  next;
 };
 local $/ = undef;
 my $contents = <FILE>;
 close FILE;
 if ($contents =~ m{<\?xml-model[^>]+href=['"]([^'"]+)"}) { return $1; }  # get RelaxNG schema
 return undef;
}

# use 'xmlcatalog' to convert URI to RelaxNG schema file name
sub get_schema_file_for_uri {
 my $uri = shift;
 my ($schema_file) = split("\n", `xmlcatalog '$catalog_file' '$uri'`);
 if ($?) {
  say STDERR "Error: Could not resolve '$uri' from '$catalog_file'.";
  return undef;
 }
 return $schema_file;
}




__END__


=head1 NAME

ditaot_validate.pl - validate DITA files against their RelaxNG schemas

=head1 SYNOPSIS

ditaot_validate.pl [options] path [path ...]

  path [path ...]
      Files or directories to validate
      (files must use RelaxNG schema via <?xml-model ...?>)
      (for directories, all .ditamap and .dita files are validated)
  [--dita /path/to/bin/dita]
      Specifies which DITA-OT installation to use for DITA grammars
      (default is from 'dita' in search path)
  [--verbose]
      Print additional information about files and schemas


For example, to validate all .dita/.ditamap files in 'my_dir/',

  ditaot_validate.pl my_dir

