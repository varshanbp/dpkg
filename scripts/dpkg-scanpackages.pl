#!/usr/bin/perl

$version= '1.2.6'; # This line modified by Makefile

%kmap= ('optional','suggests',
        'recommended','recommends',
        'class','priority',
        'package_revision','revision');

@fieldpri= ('Package',
            'Version',
            'Priority',
            'Section',
            'Essential',
            'Maintainer',
            'Pre-Depends',
            'Depends',
            'Recommends',
            'Suggests',
            'Conflicts',
            'Provides',
            'Replaces',
            'Architecture',
            'Filename',
            'Size',
            'MD5sum',
            'Description');

$i=100; grep($pri{$_}=$i--,@fieldpri);

$#ARGV == 1 || $#ARGV == 2
    or die "Usage: dpkg-scanpackages binarypath overridefile pathprefix > Packages\n";
($binarydir, $override, $pathprefix) = @ARGV;
-d $binarydir or die "Binary dir $binarydir not found\n";
-e $override or die "Override file $override not found\n";

# The extra slash causes symlinks to be followed.
open(F,"find $binarydir/ -follow -name '*.deb' -print |")
    or die "Couldn't open pipe to find: $!\n";
while (<F>) {
    chop($fn=$_);
    substr($fn,0,length($binarydir)) eq $binarydir
	or die "$fn not in binary dir $binarydir\n";
    $t= `dpkg-deb -I $fn control`
	or die "Couldn't call dpkg-deb on $fn: $!\n";
    $? and die "\`dpkg-deb -I $fn control' exited with $?\n";
    undef %tv;
    $o= $t;
    while ($t =~ s/^\n*(\S+):[ \t]*(.*(\n[ \t].*)*)\n//) {
        $k= lc $1; $v= $2;
        if (defined($kmap{$k})) { $k= $kmap{$k}; }
        if (@kn= grep($k eq lc $_, @fieldpri)) {
            @kn==1 || die $k;
            $k= $kn[0];
        }
        $v =~ s/\s+$//;
        $tv{$k}= $v;
    }
    $t =~ /^\n*$/
	or die "Unprocessed text from $fn control file; info:\n$o / $t\n";

    defined($tv{'Package'})
	or die "No Package field in control file of $fn\n";
    $p= $tv{'Package'}; delete $tv{'Package'};

    if (defined($p1{$p})) {
        print(STDERR " ! Package $p (filename $fn) is repeat;\n".
                     "   ignored that one and using data from $pfilename{$p} !\n")
            || die $!;
        next;
    }
    print(STDERR " ! Package $p (filename $fn) has Filename field!\n") || die $!
        if defined($tv{'Filename'});
    
    $tv{'Filename'}= "$pathprefix$fn";

    open(C,"md5sum <$fn |") || die "$fn $!";
    chop($_=<C>); close(C); $? and die "\`md5sum < $fn' exited with $?\n";
    /^[0-9a-f]{32}$/ or die "Strange text from \`md5sum < $fn': \`$_'\n";
    $tv{'MD5sum'}= $_;

    @stat= stat($fn) or die "Couldn't stat $fn: $!\n";
    $stat[7] or die "$fn is empty\n";
    $tv{'Size'}= $stat[7];

    if (length($tv{'Revision'})) {
        $tv{'Version'}.= '-'.$tv{'Revision'};
        delete $tv{'Revision'};
    }

    for $k (keys %tv) {
        $pv{$p,$k}= $tv{$k};
        $k1{$k}= 1;
        $p1{$p}= 1;
    }

    $_= substr($fn,length($binarydir));
    s#/[^/]+$##; s#^/*##;
    $psubdir{$p}= $_;
    $pfilename{$p}= $fn;
}
close(F);
$? and die "find exited with $?\n";

select(STDERR); $= = 1000; select(STDOUT);

format STDERR =
  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$packages
.

sub writelist {
    $title= shift(@_);
    return unless @_;
    print(STDERR " $title\n") || die $!;
    $packages= join(' ',sort @_);
    while (length($packages)) { write(STDERR) || die $!; }
    print(STDERR "\n") || die $!;
}

@samemaint=();

open(O, $override)
    or die "Couldn't open override file $override: $!\n";
while (<O>) {
    s/\#.*//;
    s/\s+$//;
    ($p,$priority,$section,$maintainer)= split(/\s+/,$_,4);
    next unless defined($p1{$p});
    if (length($maintainer)) {
        if ($maintainer =~ m/\s*=\>\s*/) {
            $oldmaint= $`; $newmaint= $'; $debmaint= $pv{$p,'Maintainer'};
            if (!grep($debmaint eq $_, split(m:\s*//\s*:, $oldmaint))) {
                push(@changedmaint,
                     "  $p (package says $pv{$p,'Maintainer'}, not $oldmaint)\n");
            } else {
                $pv{$p,'Maintainer'}= $newmaint;
            }
        } elsif ($pv{$p,'Maintainer'} eq $maintainer) {
            push(@samemaint,"  $p ($maintainer)\n");
        } else {
            print(STDERR " * Unconditional maintainer override for $p *\n") || die $!;
            $pv{$p,'Maintainer'}= $maintainer;
        }
    }
    $pv{$p,'Priority'}= $priority;
    $pv{$p,'Section'}= $section;
    ($sectioncut = $section) =~ s:^[^/]*/::;
    if (length($psubdir{$p}) && $section ne $psubdir{$p} &&
	$sectioncut ne $psubdir{$p}) {
    if (length($psubdir{$p}) && $section ne $psubdir{$p}) {
        print(STDERR " !! Package $p has \`Section: $section',".
                     " but file is in \`$psubdir{$p}' !!\n") || die $!;
        $ouches++;
    }
    $o1{$p}= 1;
}
close(O);
print(STDERR "\n") || die $! if $ouches;

$k1{'Maintainer'}= 1;
$k1{'Priority'}= 1;
$k1{'Section'}= 1;

@missingover=();

for $p (sort keys %p1) {
    if (!defined($o1{$p})) {
        push(@missingover,$p);
    }
    $r= "Package: $p\n";
    for $k (sort { $pri{$b} <=> $pri{$a} } keys %k1) {
        next unless length($pv{$p,$k});
        $r.= "$k: $pv{$p,$k}\n";
    }
    $r.= "\n";
    $written++;
    $p1{$p}= 1;
    print(STDOUT $r) or die "Failed when writing stdout: $!\n";
}
close(STDOUT) or die "Couldn't close stdout: $!\n";

@spuriousover= grep(!defined($p1{$_}),sort keys %o1);

&writelist("** Packages in archive but missing from override file: **",
           @missingover);
if (@changedmaint) {
    print(STDERR
          " ++ Packages in override file with incorrect old maintainer value: ++\n",
          @changedmaint,
          "\n") || die $!;
}
if (@samemaint) {
    print(STDERR
          " -- Packages specifying same maintainer as override file: --\n",
          @samemaint,
          "\n") || die $!;
}
if (@spuriousover) {
    print(STDERR
          " -- Packages in override file but not in archive: --\n",
          @spuriousover,
          "\n") || die $!;
}

print(STDERR " Wrote $written entries to output Packages file.\n") || die $!;
