import { Game, Platform } from './types';

const CSV_HEADERS = [
  'Name',
  'Platform',
  'Acquired',
  'Target Price',
  'Priority',
  'Purchase Price',
  'Acquisition Date',
  'Seller',
  'Notes'
];

export function generateBlankCSV(): string {
  return CSV_HEADERS.join(',') + '\n';
}

export function exportGamesToCSV(games: Game[]): string {
  const rows = [CSV_HEADERS.join(',')];
  
  games.forEach(game => {
    const row = [
      escapeCSVField(game.name),
      game.platform,
      game.acquired ? 'Yes' : 'No',
      game.targetPrice?.toString() || '',
      game.priority ? 'Yes' : 'No',
      game.purchasePrice?.toString() || '',
      game.acquisitionDate || '',
      escapeCSVField(game.seller || ''),
      escapeCSVField(game.notes || '')
    ];
    rows.push(row.join(','));
  });
  
  return rows.join('\n');
}

export function parseCSV(csvContent: string): { games: Game[], errors: string[] } {
  const lines = csvContent.split('\n').filter(line => line.trim());
  const errors: string[] = [];
  const games: Game[] = [];
  
  if (lines.length === 0) {
    errors.push('CSV file is empty');
    return { games, errors };
  }
  
  const headers = parseCSVLine(lines[0]);
  
  for (let i = 1; i < lines.length; i++) {
    const lineNum = i + 1;
    const values = parseCSVLine(lines[i]);
    
    if (values.length === 0) continue;
    
    if (values.length !== headers.length) {
      errors.push(`Line ${lineNum}: Expected ${headers.length} columns, got ${values.length}`);
      continue;
    }
    
    const [name, platform, acquired, targetPrice, priority, purchasePrice, acquisitionDate, seller, notes] = values;
    
    if (!name || !name.trim()) {
      errors.push(`Line ${lineNum}: Game name is required`);
      continue;
    }
    
    if (!['PS1', 'PS2', 'PS3', 'PSP', 'PC'].includes(platform)) {
      errors.push(`Line ${lineNum}: Invalid platform "${platform}". Must be PS1, PS2, PS3, PSP, or PC`);
      continue;
    }
    
    const isAcquired = acquired.toLowerCase() === 'yes' || acquired === '1' || acquired.toLowerCase() === 'true';
    const isPriority = priority.toLowerCase() === 'yes' || priority === '1' || priority.toLowerCase() === 'true';
    
    const game: Game = {
      id: crypto.randomUUID(),
      name: name.trim(),
      platform: platform as Platform,
      acquired: isAcquired,
      targetPrice: targetPrice ? parseFloat(targetPrice) : undefined,
      priority: isPriority || undefined,
      purchasePrice: purchasePrice ? parseFloat(purchasePrice) : undefined,
      acquisitionDate: acquisitionDate || undefined,
      seller: seller || undefined,
      notes: notes || undefined
    };
    
    games.push(game);
  }
  
  return { games, errors };
}

function escapeCSVField(field: string): string {
  if (field.includes(',') || field.includes('"') || field.includes('\n')) {
    return `"${field.replace(/"/g, '""')}"`;
  }
  return field;
}

function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;
  
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    const nextChar = line[i + 1];
    
    if (char === '"') {
      if (inQuotes && nextChar === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }
  
  result.push(current);
  return result;
}

export function downloadCSV(content: string, filename: string): void {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  const url = URL.createObjectURL(blob);
  
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}
