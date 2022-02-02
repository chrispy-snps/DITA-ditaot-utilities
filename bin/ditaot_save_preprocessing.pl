#!/usr/bin/perl
use warnings;
use strict;
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

# find where the build*.xml file lives
$dita = File::Spec->rel2abs($dita);  # get absolute path (can be <DITA-OT> or <DITA-OT>/bin/dita)
my $dita_dir = ($dita =~ s!\/(bin/.*)?$!!rs) or die "could not get DITA-OT root directory";  # remove trailing slash, 'bin/*'
die "could not find '$dita_dir'" if !-d $dita_dir;
print "Using the DITA-OT installation at '$dita_dir'.\n";
my $buildfile = "$dita_dir/plugins/org.dita.base/build_${pipeline}.xml";
die "could not find '$buildfile'" if !-f $buildfile;

# this is where the original build*.xml file is saved
my $orig_buildfile = "${buildfile}.orig";

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

if ($add) {
 # make a backup copy of the build*.xml file, if it doesn't already exist
 if (!-f $orig_buildfile) {
  File::Copy::copy($buildfile, $orig_buildfile);
  print "Copied '$buildfile'\n    to '$orig_buildfile'.\n\n";
 }

 # read the build*.xml file
 my $twig = XML::Twig->new(
  twig_handlers => {
  })->parsefile($orig_buildfile);

 # get the list of sub-targets called by the top-level target
 my $pipeline_elt = $twig->first_elt("target[\@name = '$pipeline']") or die "could not find <target name='$pipeline'> in '$buildfile'";
 my @depends = split(m![,\s]+!, $pipeline_elt->att('depends'));

 # add our modifications at end of each sub-target <target> element
 my $idx = 1;
 foreach my $subtarget (@depends) {
  my $sub_target_elt = $twig->first_elt("target[\@name = '$subtarget']") or next;  # skip to next if we can't find it
  my $dest_dir = sprintf('${dita.temp.dir}-%d-%s', $idx++, $subtarget);

  # print a helpful message during DITA-OT transformation
  $sub_target_elt->insert_new_elt(last_child => 'echo', "Copying temporary files to '$dest_dir'.");

  # do a straight <copy> of everything with no modification
  if (0) {
   $sub_target_elt
    ->insert_new_elt(last_child => 'copy', {todir => $dest_dir})
    ->insert_new_elt(last_child => 'fileset', {dir => '${dita.temp.dir}'});
  }

  # use <xslt> to simpify files
  if (1) {
   $sub_target_elt
    ->insert_new_elt(last_child => 'xslt', {style => $xslt_file, basedir => '${dita.temp.dir}', destdir => $dest_dir, includes => '**/*.dita*'})
    ->insert_new_elt(last_child => 'mapper', {type => 'identity'});
  }

  print "  '$subtarget' will save results in '$dest_dir'.\n";
 }

 $twig->print_to_file($buildfile, pretty_print => 'indented');
 print "Wrote modifications to '$buildfile'.\n";

 # write out our XSLT file
 write_entire_file($xslt_file, $XSLT);
 print "Wrote simplification XSLT to '$xslt_file'.\n";

} elsif ($remove) {
 # restore original build* file
 if (-f $orig_buildfile) {
  print "Restored '$orig_buildfile'\n      to '$buildfile'.\n";
  File::Copy::copy($orig_buildfile, $buildfile);
  unlink($orig_buildfile);
  unlink($xslt_file);
 } else {
  print "Error: No DITA-OT modifications installed.\n";
  exit 1;
 }
}

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

