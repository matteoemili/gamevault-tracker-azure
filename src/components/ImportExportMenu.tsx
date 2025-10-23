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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
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
  const [showExportDialog, setShowExportDialog] = useState(false);
  const [selectedCategories, setSelectedCategories] = useState<Set<string>>(new Set());
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleDownloadTemplate = () => {
    const csv = generateBlankCSV();
    downloadCSV(csv, 'game-collection-template.csv');
    toast.success('Template downloaded');
  };

  const handleExportClick = () => {
    setSelectedCategories(new Set(categories.map(c => c.id)));
    setShowExportDialog(true);
  };

  const handleToggleCategory = (categoryId: string) => {
    setSelectedCategories(prev => {
      const newSet = new Set(prev);
      if (newSet.has(categoryId)) {
        newSet.delete(categoryId);
      } else {
        newSet.add(categoryId);
      }
      return newSet;
    });
  };

  const handleSelectAll = () => {
    setSelectedCategories(new Set(categories.map(c => c.id)));
  };

  const handleSelectNone = () => {
    setSelectedCategories(new Set());
  };

  const handleExport = () => {
    const filteredGames = selectedCategories.size === categories.length
      ? games
      : games.filter(game => selectedCategories.has(game.platform));

    if (filteredGames.length === 0) {
      toast.error('No games to export with selected categories');
      return;
    }
    
    const csv = exportGamesToCSV(filteredGames);
    const fileName = selectedCategories.size === categories.length
      ? `game-collection-${new Date().toISOString().split('T')[0]}.csv`
      : `game-collection-${categories.filter(c => selectedCategories.has(c.id)).map(c => c.name).join('-')}-${new Date().toISOString().split('T')[0]}.csv`;
    
    downloadCSV(csv, fileName);
    toast.success(`Exported ${filteredGames.length} ${filteredGames.length === 1 ? 'game' : 'games'}`);
    setShowExportDialog(false);
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
          <DropdownMenuItem onClick={handleExportClick} disabled={games.length === 0}>
            <DownloadSimple className="mr-2" />
            Export Games
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

      <Dialog open={showExportDialog} onOpenChange={setShowExportDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Export Games</DialogTitle>
            <DialogDescription>
              Select which categories to include in the export
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4 py-4">
            <div className="flex justify-end gap-2 pb-2">
              <Button
                variant="ghost"
                size="sm"
                onClick={handleSelectAll}
              >
                Select All
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleSelectNone}
              >
                Select None
              </Button>
            </div>
            
            {categories.map((category) => {
              const count = games.filter(g => g.platform === category.id).length;
              return (
                <div key={category.id} className="flex items-center space-x-3">
                  <Checkbox
                    id={`category-${category.id}`}
                    checked={selectedCategories.has(category.id)}
                    onCheckedChange={() => handleToggleCategory(category.id)}
                    disabled={count === 0}
                  />
                  <Label
                    htmlFor={`category-${category.id}`}
                    className={`flex-1 text-sm font-medium cursor-pointer ${count === 0 ? 'opacity-50' : ''}`}
                  >
                    {category.name} ({count} {count === 1 ? 'game' : 'games'})
                  </Label>
                </div>
              );
            })}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowExportDialog(false)}>
              Cancel
            </Button>
            <Button onClick={handleExport} disabled={selectedCategories.size === 0}>
              <DownloadSimple className="mr-2" />
              Export {selectedCategories.size > 0 && `(${games.filter(g => selectedCategories.has(g.platform)).length})`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
