# WikiLumper
The tool for migration from Dokuwiki and XWiki to Atlassian Confluence: easy and for free

## Table of Contents

  1. [Capabilities](#capabilities)
  1. [Migrate Dokuwiki](#migrate-dokuwiki)
  1. [Migrate XWiki](#migrate-xwiki)
  1. [Some notes](#do-job)
  1. [Needed Perl modules](#perl-modules)

## Capabilities
WikiLumper can:

  * Copy all articles
  * Copy all attachments
  * Translate markup (at best effort)
  * Save the pages hierarchy

WikiLumper can not:

  * Save authors
  * Save history

## Migrate Dokuwiki
  Dokuwiki stores all the articles as simple txt files and all the attachments as ordinary files on the filesystem. Just copy the folders with pages and media to the machine from where you plan to do the job. Then edit config.pl and define the path to these folders in 'pages' and 'media' keys. Then configure the Confluence parameters and run migrate.pl.
  All the pages that could not be accessed by links will be placed under "Orphaned pages".

## Migrate XWiki
  You can export the archive of the XWiki pages by accessing the url http://yourwikiserver/xwiki/bin/export/Space/Page?format=xar. Unarchive the downloaded xar-file, look through the folder and delete unneeded ones. All the articles are stores as xml files with all the attachments encoded as base64 in them. Edit config.pl: define the path to your unarchived backup and configure Confluence settings. Then just run migrate.pl.

## Some notes
  First you will need to rename config.pl_example to config.pl and edit it for your needs. You will have no problems with it if you have some familiarity with Perl syntax (even if not).
  Then you just run the script:
  > ./migrate.pl [--debug]

  It is a good idea to create a fresh Confluence space for the migration. If the migration goes well then you just move the migrated data to your working space. If the migration fails or the results are not satisfying then you can just drop the space and repeat or look for some other options.


## Needed Perl modules
  * LWP::UserAgent
  * JSON
  * MIME::Base64
  * Data::Dumper
  * Getopt::Long
  * XML::Parser
