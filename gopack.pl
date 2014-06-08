#!/usr/bin/env perl
#
# Copyright (c) 2014. Aleksandar Veselinovic (http://aleksa.org).
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


use v5.010;

use File::Basename;
use File::Spec;
use File::Temp qw(mktemp);
use MIME::Base64;

use strict;
use warnings;

my $GOTEMPLATE = q|package main

import (
	"archive/zip"
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
)

type GoPackMap map[string]([]byte)

const data = `
{{ ZIP DATA }}`

func unZipInMemory(archive []byte) (GoPackMap, error) {
	var (
		err           error
		reader        *zip.Reader
		reader_closer io.ReadCloser
		size          int64
		check_cnt     int
	)

	data := make(GoPackMap)
	size = int64(len(archive))

	archive_reader := bytes.NewReader(archive)
	if reader, err = zip.NewReader(archive_reader, size); err != nil {
		return nil, err
	}

	check_cnt = 1
	for _, f := range reader.File {
		var total_bytes_read uint64

		if f.Mode().IsDir() { // if file is a directory
			continue
		}

		if reader_closer, err = f.Open(); err != nil {
			return nil, err
		}

		// Open an in-memory file. Use UncompressedSize64 from the FileHeader.
		file_content := make([]byte, f.FileHeader.UncompressedSize64)

		total_bytes_read = 0
		for total_bytes_read < f.FileHeader.UncompressedSize64 {
			var bytes_read int
			if bytes_read, err = reader_closer.Read(file_content[total_bytes_read:]); err != nil {
				return nil, err
			}
			total_bytes_read += uint64(bytes_read)
		}

		if total_bytes_read != f.FileHeader.UncompressedSize64 {
			return nil, fmt.Errorf("Unpacked and expected to unpack %d but got %d",
				total_bytes_read, f.FileHeader.UncompressedSize64)
		}
		data[f.Name] = file_content
		//<TESTCODE>
		fmt.Println("ok", check_cnt, "-", f.Name, "-> unpacked", total_bytes_read,
			"of expected", f.FileHeader.UncompressedSize64, "bytes.")
		//</TESTCODE>
		reader_closer.Close()
		check_cnt++
	}
	return data, nil
}

func GetFileMap() GoPackMap {
	var (
		file_map     GoPackMap
		decoded_data []byte
		err          error
	)
	if decoded_data, err = base64.StdEncoding.DecodeString(data); err != nil {
		panic(err)
	}
	if file_map, err = unZipInMemory(decoded_data); err != nil {
		panic("Couldn't unpack required data!")
	}
	return file_map
}

//<TESTCODE>
func main() {
	fmt.Println("# Checking everything was packed correctly!")
	data := GetFileMap()
	fmt.Println("# Entries in stored data map:")
	file_counter := 1
	for k, _ := range data {
		fmt.Printf("# %d\t-> %s\n", file_counter, k)
		file_counter++
	}
}
//</TESTCODE>|;


my @FILES_TO_DELETE;


sub register_for_deletion {
	my $file = shift;
	say "Registered '${file}' for deletion.";
	push @FILES_TO_DELETE, $file;
}


sub expected_number_of_files {
	my $dir = shift;
	chomp(my $file_count = `find ${dir} -follow -type f | wc -l`);
	return $file_count + 0;
}


sub zip_and_encode {
	my $dir = shift;

	my $name = mktemp('gopack-tmp-XXXXX') . '.zip';
	say STDERR "Packing data to '$name':";

	chomp(my $out = `zip -9r ${name} ${dir}/*`);
	die($out) if $?;
	say STDERR $out;
	register_for_deletion($name);


	my $base64_data;
	{
		open(my $fh, '<', $name) or die("Cannot read open '${name}': $!");
		binmode($fh);
		local $/;
		$base64_data = encode_base64(<$fh>);
		close($fh);
	}
	return \$base64_data;
}


sub create_gopack_file {
	my $base64_data_ref = shift;
	my $dir = shift;

	(my $gocode = $GOTEMPLATE) =~ s/{{ ZIP DATA }}/$$base64_data_ref/;

	my $src_name = "gopack_checks.go";
	say STDERR "Writing GoLang code to '${src_name}'.";
	{
		open(my $fh, '>', $src_name) or die("Cannot write to '$src_name': $!");
		print $fh $gocode;
		close($fh);
	}

 	my $expected_file_count = expected_number_of_files($dir);
	say STDERR "Expected number of packed files: ${expected_file_count}.";
	chomp(my $gorun_out = `go run $src_name`);
	die($gorun_out) if $?;
	say "1..${expected_file_count}";
	say $gorun_out;

	my $go_reported_file_count = grep {/\t-> /} split("\n", $gorun_out);
	say STDERR "Go packed ${go_reported_file_count} files, out of expected ${expected_file_count}.";
	if ($go_reported_file_count != $expected_file_count) {
		say STDERR "Possible ERROR? Run a manual check if everything was packed correctly.";
	} else {
		register_for_deletion($src_name);
	}

	my $final_src_name = "gopack.go";
	$gocode =~ s|//<TESTCODE>.*?//</TESTCODE>||sg;
	say STDERR "Writing final GoLang code to '${final_src_name}'.";
	{
		open(my $fh, '>', $final_src_name) or die("Cannot write to '${final_src_name}': $!");
		print $fh $gocode;
		close($fh);
	}
	say STDERR "Running gofmt on '${final_src_name}'.";
	chomp($gorun_out = `gofmt -w ${final_src_name}`);
	die($gorun_out) if $?;
}


sub main {
	my $dir = shift;
	die('No directory specified!') unless defined $dir;
	die('Must specify a directory!') unless -d $dir;
	die('Avoid using ".." when specifying directories.') if $dir =~ /\.\./;

	say STDERR "GoPacker Started!";
	$dir =  File::Spec->canonpath($dir);
	say STDERR "Packing '${dir}/'.";

	my $base64_data_ref = zip_and_encode($dir);
	create_gopack_file($base64_data_ref, $dir);
	say STDERR "GoPacker is Done.";
}


main(@ARGV);


END {
	foreach my $file (@FILES_TO_DELETE) {
		say "Deleting '${file}'.";
		unlink $file;
	}
}
