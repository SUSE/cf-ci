#!/bin/sh
# This just removes the server part from the image name; this is required
# because the dockerfile that will use this image to build the next image has a
# FROM line that doesn't include the server part.
set -o xtrace -o errexit -o nounset
tar -cC in . | tar -xC out
sed -i s@^.*/@@ out/repository
