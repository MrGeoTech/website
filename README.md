# My Personal Website

This repo contains the code for my [personal website](https://isaacgeorge.net).

Feel free to download and run the website locally using `zig build run`. I plan to continue improving
the markdown parser so any optimizations or tips are greatly appreciated.

### Markdown Parser

This repo implements my own markdown to HTML converter because other parsers don't seem to handle
math quite right. My implementation, though not perfect, is enough to post the articles I wish to
post. Currently, the only unimplemented feature is [Reference-style Links](https://www.markdownguide.org/basic-syntax/#reference-style-links).
