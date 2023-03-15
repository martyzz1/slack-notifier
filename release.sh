#!/usr/bin/env bash

SCOPE="$1"

if [ -z "$SCOPE" ]; then
  SCOPE="auto"
fi

echo "Using scope $SCOPE"

# We get the next version, without tagging
echo "Getting next version"
nextversion=$(./semtag final -fos "$SCOPE")
echo "Publishing with version: $nextversion"

# We update the tag with the new version
./semtag final -f -v "$nextversion"
