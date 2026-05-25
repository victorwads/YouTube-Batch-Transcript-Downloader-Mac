# YouTube Transcript Batch Mac

A desktop app built with Electron and TypeScript for batch-extracting YouTube transcripts from a text input that contains titles and links together.

## What it does

- Reads pasted text with mixed titles and YouTube links
- Extracts the links and shows them in a structured list
- Opens up to six live WebViews in parallel to collect transcripts
- Keeps the final results in the same order as the links appear in the input
- Caches transcripts locally to avoid repeating work
- Exports the final result to a `.txt` file

## Requirements

- macOS
- Node.js
- Electron
- TypeScript

## How to use it

1. Paste the input text with titles and YouTube links into the main field.
2. Run `npm start`.
3. Watch the live WebViews while the app works through the batch.
4. Review the final output concatenated with title, link, and transcript.
5. Export everything to `.txt` if you want to keep a text file copy.

## Notes

- This app is built specifically for macOS using Electron.
- The local cache reuses transcripts that were already extracted.
- The final output always respects the original input order.
