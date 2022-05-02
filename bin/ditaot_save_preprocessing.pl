#!/usr/bin/perl
use warnings;
use strict;
use v5.10;  # for "state" and "//" features
use File::Copy;
use File::Spec;
use Getopt::Long 'HelpMessage';
use XML::Twig;


# process command-line arguments
my $dita;
my $pipeline = 'preprocess';  # you can change the default here
my $add;
my $remove;
GetOptions(
  'dita=s'     => \$dita,
  'pipeline=s' => \$pipeline,
  'add'        => \$add,
  'remove'     => \$remove,
  'help'       => sub { HelpMessage(0) }
  ) or HelpMessage(1);

# validate the command-line arguments
if (!defined($pipeline) || ($pipeline ne 'preprocess' && $pipeline ne 'preprocess2')) {
 print "Must specify --pipeline preprocess' or '--pipeline preprocess2'.\n";
 HelpMessage(1);
}

if ((!$add && !$remove) || ($add && $remove)) {
 print "Error: Must specify --add or --remove (but not both).\n";
 HelpMessage(1);
}

if (!defined($dita)) {
 # if not specified, look for 'dita' in the current search path
 $dita = (`which dita` =~ s!\R$!!r);  # try to get a default
 die "cannot find 'dita' in search path (use --dita to specify DITA-OT location)" if $dita eq '';
}

# find where the DITA-OT directory is
$dita = File::Spec->rel2abs($dita);  # get absolute path (can be <DITA-OT> or <DITA-OT>/bin/dita)
my $dita_dir = ($dita =~ s!\/(bin/.*)?$!!rs) or die "could not get DITA-OT root directory";  # remove trailing slash, 'bin/*'
die "could not find '$dita_dir'" if !-d $dita_dir;
print "Using the DITA-OT installation at '$dita_dir'.\n";

# this is the XSLT used to simplify .dita* files
my $xslt_file = "$dita_dir/plugins/org.dita.base/clean.xsl";
my $XSLT = <<'EOS';
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:dita="mine"
  xmlns:dita-ot="http://dita-ot.sourceforge.net/ns/201007/dita-ot"
  xmlns:ditaarch="http://dita.oasis-open.org/architecture/2005/"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  version="2.0">

  <xsl:strip-space elements="*"/>
  <xsl:output method="xml" indent="yes"/>

  <!-- baseline identity transform -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="processing-instruction('ditaot')"/>
  <xsl:template match="processing-instruction('path2project')"/>
  <xsl:template match="processing-instruction('path2project-uri')"/>
  <xsl:template match="processing-instruction('path2rootmap-uri')"/>
  <xsl:template match="processing-instruction('workdir')"/>
  <xsl:template match="processing-instruction('workdir-uri')"/>
  <xsl:template match="processing-instruction('xml-model')"/>

  <xsl:template match="@class"/>
  <xsl:template match="@dita-ot:orig-class"/>
  <xsl:template match="@dita-ot:orig-format"/>
  <xsl:template match="@dita-ot:orig-href"/>
  <xsl:template match="@dita-ot:submap-DITAArchVersion"/>
  <xsl:template match="@dita-ot:submap-class"/>
  <xsl:template match="@dita-ot:submap-cascade"/>
  <xsl:template match="@dita-ot:submap-domains"/>
  <xsl:template match="@dita-ot:submap-specializations"/>
  <xsl:template match="@dita-ot:submap-xtrc"/>
  <xsl:template match="@dita-ot:submap-xtrf"/>
  <xsl:template match="@ditaarch:DITAArchVersion"/>
  <xsl:template match="@ditaarch:ditaarchversion"/>
  <xsl:template match="@domains"/>
  <xsl:template match="@specializations"/>
  <xsl:template match="@xtrc"/>
  <xsl:template match="@xtrf"/>

</xsl:stylesheet>
EOS

# these are the build files to process
my @build_files = (
 "$dita_dir/plugins/org.dita.base/build_preprocess.xml",
 "$dita_dir/plugins/org.dita.base/build_preprocess2.xml"
);

# if we're removing the modifications, do it and exit here
if ($remove) {
 # restore original build* files
 foreach my $build_file (@build_files) {
  my $orig_build_file = "${build_file}.orig";
  if (-f $orig_build_file) {
   print "Restored '$orig_build_file'\n      to '$build_file'.\n";
   File::Copy::copy($orig_build_file, $build_file);
   unlink($orig_build_file);
   unlink($xslt_file);
  }
 }
 exit;
}

# we're modifying the files, so read them in
my %build_twigs = ();
my %target_elts = ();
{
 foreach my $this_build_file (@build_files) {
  # this is where the original build*.xml file is saved
  my $orig_build_file = "${this_build_file}.orig";

  # make a backup copy of the build file, if it doesn't already exist
  if (!-f $orig_build_file) {
   File::Copy::copy($this_build_file, $orig_build_file);
   print "Copied '$this_build_file'\n    to '$orig_build_file'.\n\n";
  }

  my $this_twig = $build_twigs{$this_build_file} = XML::Twig->new(
   twig_handlers => {
    'target[@name]' => sub { $target_elts{$_->att('name')} = $_; return 1; },
   })->parsefile($orig_build_file);
  $this_twig->root->set_att('#file', $this_build_file);
 }
}

# this subroutine modifies a target to save temporary files, if needed
sub process_target {
 state $idx = 1;
 my $this_target = shift;
 my $target_elt = $target_elts{$this_target} or return;

 # recurse into dependency targets first
 process_target($_) for split(m!\s*,\s*!, $target_elt->att('depends') // '');

 # now process this target
 if ($target_elt->first_child('pipeline')) {
  my $dest_dir = sprintf('${dita.temp.dir}-%02d-%s', $idx++, $this_target);

  # print a helpful message during DITA-OT transformation
  $target_elt->insert_new_elt(last_child => 'echo', "Copying temporary files to '$dest_dir'.");

  # do a straight <copy> of everything with no modification
  if (0) {
   $target_elt
    ->insert_new_elt(last_child => 'copy', {todir => $dest_dir})
    ->insert_new_elt(last_child => 'fileset', {dir => '${dita.temp.dir}'});
  }

  # use <xslt> to simpify files
  if (1) {
   $target_elt
    ->insert_new_elt(last_child => 'xslt', {style => $xslt_file, basedir => '${dita.temp.dir}', destdir => $dest_dir, includes => '**/*.dita*'})
    ->insert_new_elt(last_child => 'mapper', {type => 'identity'});
  }

  # set a marker that we need to write this build file out
  $target_elt->root->set_att('#modified', 1);

  print "  '$this_target' will save results in '$dest_dir'.\n";
 }
}

# modify the processing pipeline of interest
process_target($pipeline);  # this will recurse into dependency targets as needed

# write out modified build files
foreach my $build_file (@build_files) {
 my $this_twig = $build_twigs{$build_file};
 next if !defined($this_twig->root->att('#modified'));

 # write out modified build file
 $this_twig->print_to_file($build_file, pretty_print => 'indented');
 print "Wrote modifications to '$build_file'.\n";
}

# write out our XSLT file
write_entire_file($xslt_file, $XSLT);
print "Wrote simplification XSLT to '$xslt_file'.\n";
exit;




# write a string to a file
sub write_entire_file {
 my ($filename, $contents) = @_;
 $contents =~ s!\n?$!\n!s;  # add LF if needed
 open(FILE, ">$filename") or die "can't open $filename for write: $!";
 binmode(FILE);  # don't convert LFs to CR/LF on Windows
 binmode(FILE, ":encoding(utf-8)");  # the UTF-8 package checks and enforces this
 print FILE $contents;
 close FILE;
}

__END__


=head1 NAME

ditaot_save_preprocessing.pl - save temporary files from DITA-OT preprocessing steps

=head1 SYNOPSIS

  [--pipeline preprocess | preprocess2]
       Specifies which preprocessing pipeline to modify (default is 'preprocess')
  [--add]
       Add preprocess copy operations to the build_<pipeline>.xml file
  [--remove]
       Remove preprocess copy operations from the build_<pipeline>.xml file
  [--dita /path/to/bin/dita]
       Specifies which DITA-OT installation to use (default is from 'dita' in search path)

