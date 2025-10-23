import { useState, useRef } from 'react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { DotsThree, DownloadSimple, UploadSimple, Tag } from '@phosphor-icons/react';
import { generateBlankCSV, exportGamesToCSV, parseCSV, downloadCSV } from '@/lib/csv';
import { Game } from '@/lib/types';
import { toast } from 'sonner';
import { CategoryDialog, PlatformCategory } from './CategoryDialog';

interface ImportExportMenuProps {
  games: Game[];
  onImport: (games: Game[]) => void;
  categories: PlatformCategory[];
  onCategoriesChange: (categories: PlatformCategory[]) => void;
}

export function ImportExportMenu({ games, onImport, categories, onCategoriesChange }: ImportExportMenuProps) {
  const [showImportDialog, setShowImportDialog] = useState(false);
  const [showCategoryDialog, setShowCategoryDialog] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleDownloadTemplate = () => {
    const csv = generateBlankCSV();
    downloadCSV(csv, 'game-collection-template.csv');
    toast.success('Template downloaded');
  };

  const handleExport = () => {
    const csv = exportGamesToCSV(games);
    downloadCSV(csv, `game-collection-${new Date().toISOString().split('T')[0]}.csv`);
    toast.success(`Exported ${games.length} games`);
  };

  const handleImportClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      const content = event.target?.result as string;
      const { games: importedGames, errors } = parseCSV(content);

      if (errors.length > 0) {
        toast.error(`Import errors: ${errors.length}`, {
          description: errors.slice(0, 3).join('\n') + (errors.length > 3 ? '\n...' : '')
        });
      }

      if (importedGames.length > 0) {
        setShowImportDialog(true);
        (window as any).__pendingImport = importedGames;
      } else {
        toast.error('No valid games found in CSV');
      }
    };

    reader.readAsText(file);
    e.target.value = '';
  };

  const confirmImport = () => {
    const pendingGames = (window as any).__pendingImport as Game[];
    if (pendingGames) {
      onImport(pendingGames);
      toast.success(`Imported ${pendingGames.length} games`);
      delete (window as any).__pendingImport;
    }
    setShowImportDialog(false);
  };

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="icon">
            <DotsThree weight="bold" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={handleDownloadTemplate}>
            <DownloadSimple className="mr-2" />
            Download Template
          </DropdownMenuItem>
          <DropdownMenuItem onClick={handleImportClick}>
            <UploadSimple className="mr-2" />
            Import CSV
          </DropdownMenuItem>
          <DropdownMenuItem onClick={handleExport} disabled={games.length === 0}>
            <DownloadSimple className="mr-2" />
            Export Collection
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setShowCategoryDialog(true)}>
            <Tag className="mr-2" />
            Manage Categories
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <input
        ref={fileInputRef}
        type="file"
        accept=".csv"
        onChange={handleFileChange}
        className="hidden"
      />

      <AlertDialog open={showImportDialog} onOpenChange={setShowImportDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Import Games</AlertDialogTitle>
            <AlertDialogDescription>
              This will add {((window as any).__pendingImport as Game[])?.length || 0} games to your collection.
              Existing games will not be affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={confirmImport}>Import</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <CategoryDialog
        open={showCategoryDialog}
        onOpenChange={setShowCategoryDialog}
        categories={categories}
        onSave={onCategoriesChange}
      />
    </>
  );
}
