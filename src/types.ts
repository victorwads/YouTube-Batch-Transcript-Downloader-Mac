export interface TranscriptInputItem {
  order: number;
  title: string;
  url: string;
}

export interface TranscriptResultItem extends TranscriptInputItem {
  transcript: string;
}

export interface ExportResult {
  canceled: boolean;
  filePath?: string;
}
