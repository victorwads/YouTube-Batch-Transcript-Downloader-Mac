# YouTube Transcript Batch Mac

A macOS app written in Swift for batch-extracting YouTube transcripts from a text input that contains titles and links together.

## What it does

- Reads pasted text with mixed titles and YouTube links
- Extracts the links and shows them in a structured list
- Opens up to six `WKWebView` instances in parallel to collect transcripts
- Keeps the final results in the same order as the links appear in the input
- Caches transcripts locally to avoid repeating work
- Exports the final result to a `.txt` file

## Requirements

- macOS
- Xcode
- XcodeGen

## How to use it

1. Paste the input text with titles and YouTube links into the main field.
2. Click `Process`.
3. Watch the live WebViews while the app works through the batch.
4. Review the final output concatenated with title, link, and transcript.
5. Export everything to `.txt` if you want to keep a text file copy.

## Notes

- This app is built specifically for macOS.
- The local cache reuses transcripts that were already extracted.
- The final output always respects the original input order.
