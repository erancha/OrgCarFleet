#!/bin/bash

npm init
npm install markdown-toc

set -x
markdown-toc -i ../README.md
# Note! Insert <!-- toc --> and <!-- tocstop --> in the required position

sleep 3
# read -p "Press enter to continue"
