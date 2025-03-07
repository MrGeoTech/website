[![wakatime](https://wakatime.com/badge/user/3543bbea-973d-4ac6-b26c-ff13ea550ecc/project/82056425-dc5e-4b8f-bd9e-51854784ebee.svg)](https://wakatime.com/badge/user/3543bbea-973d-4ac6-b26c-ff13ea550ecc/project/82056425-dc5e-4b8f-bd9e-51854784ebee)

# My Personal Website

This repo contains the code for my [personal website](https://isaacgeorge.net).

Feel free to download and run the website locally using `zig build run`. I plan to continue improving
the markdown parser so any optimizations or tips are greatly appreciated.

### Markdown Parser

This repo implements my own markdown to HTML converter because other parsers don't seem to handle
math quite right. My implementation, though not perfect, is enough to post the articles I wish to
post. Currently, the only unimplemented feature is [Reference-style Links](https://www.markdownguide.org/basic-syntax/#reference-style-links).
