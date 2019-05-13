# Google DNS Updates

Script for automating the updates of Google Domains hosted synthetic DNS records.

## Overview
Google provies a robust hosted DNS solution, and offers a mechanism for hosting records that are often updated. Most providers call these 'Dynamic' DNS records. Google calls them synthetic. Further, most providers have a single account used for updating all hosted DNS records. Google, thankfully, offers more discrete security, and each record has a unique username/password for the record.

This PowerShell script is meant to help automate this updating. In my use case, I use this script on my home network, where my ISP updates my external IP often. So the script runs each day, gets my external IP address, and updates each record I've configured it to manage.

More details & info are at the blog article here: https://tsull360.wordpress.com/2019/05/13/google-dns-updates/
