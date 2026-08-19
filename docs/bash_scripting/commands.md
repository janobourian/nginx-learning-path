# Commands to start with bash scripting

You can check the command list for your OS [here](https://ss64.com)

## Command list

* `uname` to have information about the operating system
* `pwd` Print Working Directory
* `cd`
* `ls`
* `less <filename>`
* `ls -la`
* `file <filename>`
* `cp`
* `mv`
* `rm`
* `rm -r`
* `mkdir`
* `type <command>`
* `which <command>`
* `help <command>`
* `man <command>`
* `cat <filename>` print the file content
* `|` pipe allows chained other commands
* `grep` display only specific information

* `>` redirection to an output file
* `cp`
* `wc` word count command used to count the number of lines, words, characters in a file or standard input

## I/O Redirection

* `>` redirect the output of a command to a file, overwriting the file if it already exists.
* `>>` redirect the output of a command to a file, appending to the file

## Examples

* `cat application.log | grep ERROR | wc -l`
