# opentgc.koplugin
Read OpenTGC posts directly from your koreader.

## Installation

[Download the repository](https://github.com/milinami/opentgc.koplugin/archive/refs/heads/main.zip) and extract its files into:
**/koreader/plugins/**

Restart KOReader to ensure the plugin is loaded correctly.

## Usage

Each OpenTGC post has a unique identifier, which can be found in the post URL.

Example:
**https://opentgc.com/post/9975561a9fe...**

In this case, the post ID is:
**9975561a9fe...**

With KOReader open, access the plugin from the search tab and enter the post ID.
The plugin will download the post content as an HTML file, along with its associated images.

The files will be saved to:
**koreader/opentgc/(id)**

After downloading, the plugin will automatically open the file.

This was done with the help of AI, so expect bugs.