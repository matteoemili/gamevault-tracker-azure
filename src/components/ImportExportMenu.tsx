import { useState, useRef, useMemo } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
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
import { DotsThree, DownloadSimple, UploadSimple, Tag, MagnifyingGlass, Star, Warning } from '@phosphor-icons/react';
import { generateBlankCSV, exportGamesToCSV, parseCSV, downloadCSV } from '@/lib/csv';
import { Game } from '@/lib/types';
import { toast } from 'sonner';
import { CategoryDialog, PlatformCategory } from './CategoryDialog';
import { PlatformLogo } from './PlatformLogo';

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
  const [pendingGames, setPendingGames] = useState<Game[]>([]);
  const [selectedGameIds, setSelectedGameIds] = useState<Set<string>>(new Set());
  const [importSearchQuery, setImportSearchQuery] = useState('');
  const [importPlatformFilter, setImportPlatformFilter] = useState<string>('all');
  const [importStatusFilter, setImportStatusFilter] = useState<'all' | 'owned' | 'wanted'>('all');
  const [importDuplicateFilter, setImportDuplicateFilter] = useState<'all' | 'duplicates' | 'new'>('all');
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
        setPendingGames(importedGames);
        setSelectedGameIds(new Set(importedGames.map(g => g.id)));
        setImportSearchQuery('');
        setImportPlatformFilter('all');
        setImportStatusFilter('all');
        setImportDuplicateFilter('all');
        setShowImportDialog(true);
      } else {
        toast.error('No valid games found in CSV');
      }
    };

    reader.readAsText(file);
    e.target.value = '';
  };

  const duplicateGames = useMemo(() => {
    const duplicateIds = new Set<string>();
    pendingGames.forEach(pendingGame => {
      const isDuplicate = games.some(
        existingGame => 
          existingGame.name.toLowerCase() === pendingGame.name.toLowerCase() &&
          existingGame.platform === pendingGame.platform
      );
      if (isDuplicate) {
        duplicateIds.add(pendingGame.id);
      }
    });
    return duplicateIds;
  }, [pendingGames, games]);

  const filteredImportGames = useMemo(() => {
    return pendingGames.filter(game => {
      const matchesSearch = game.name.toLowerCase().includes(importSearchQuery.toLowerCase());
      const matchesPlatform = importPlatformFilter === 'all' || game.platform === importPlatformFilter;
      const matchesStatus = 
        importStatusFilter === 'all' ||
        (importStatusFilter === 'owned' && game.acquired) ||
        (importStatusFilter === 'wanted' && !game.acquired);
      
      const matchesDuplicate = 
        importDuplicateFilter === 'all' ||
        (importDuplicateFilter === 'duplicates' && duplicateGames.has(game.id)) ||
        (importDuplicateFilter === 'new' && !duplicateGames.has(game.id));
      
      return matchesSearch && matchesPlatform && matchesStatus && matchesDuplicate;
    });
  }, [pendingGames, importSearchQuery, importPlatformFilter, importStatusFilter, importDuplicateFilter, duplicateGames]);

  const importPlatformCounts = useMemo(() => {
    const counts: Record<string, number> = { all: pendingGames.length };
    
    categories.forEach(cat => {
      counts[cat.id] = 0;
    });
    
    pendingGames.forEach(game => {
      if (counts[game.platform] !== undefined) {
        counts[game.platform]++;
      }
    });
    
    return counts;
  }, [pendingGames, categories]);

  const handleToggleGame = (gameId: string) => {
    setSelectedGameIds(prev => {
      const newSet = new Set(prev);
      if (newSet.has(gameId)) {
        newSet.delete(gameId);
      } else {
        newSet.add(gameId);
      }
      return newSet;
    });
  };

  const handleSelectAllImport = () => {
    setSelectedGameIds(new Set(filteredImportGames.map(g => g.id)));
  };

  const handleSelectNoneImport = () => {
    setSelectedGameIds(new Set());
  };

  const confirmImport = () => {
    const gamesToImport = pendingGames.filter(g => selectedGameIds.has(g.id));
    const duplicatesInSelection = gamesToImport.filter(g => duplicateGames.has(g.id)).length;
    
    if (gamesToImport.length > 0) {
      onImport(gamesToImport);
      if (duplicatesInSelection > 0) {
        toast.success(`Imported ${gamesToImport.length} ${gamesToImport.length === 1 ? 'game' : 'games'}`, {
          description: `${duplicatesInSelection} duplicate${duplicatesInSelection !== 1 ? 's' : ''} included`
        });
      } else {
        toast.success(`Imported ${gamesToImport.length} ${gamesToImport.length === 1 ? 'game' : 'games'}`);
      }
    }
    setShowImportDialog(false);
    setPendingGames([]);
    setSelectedGameIds(new Set());
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

      <Dialog open={showImportDialog} onOpenChange={setShowImportDialog}>
        <DialogContent className="max-w-4xl max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>Import Games</DialogTitle>
            <DialogDescription>
              Review and select games to import. {selectedGameIds.size} of {pendingGames.length} games selected.
              {duplicateGames.size > 0 && (
                <span className="block mt-1 text-amber-600 dark:text-amber-500">
                  {duplicateGames.size} duplicate{duplicateGames.size !== 1 ? 's' : ''} detected
                </span>
              )}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 flex-1 min-h-0 flex flex-col">
            <div className="flex flex-col sm:flex-row gap-3">
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" size={16} />
                <Input
                  placeholder="Search games..."
                  value={importSearchQuery}
                  onChange={(e) => setImportSearchQuery(e.target.value)}
                  className="pl-9"
                />
              </div>
              
              <div className="flex gap-2">
                <Button
                  variant={importStatusFilter === 'all' ? 'default' : 'outline'}
                  onClick={() => setImportStatusFilter('all')}
                  size="sm"
                >
                  All
                </Button>
                <Button
                  variant={importStatusFilter === 'owned' ? 'default' : 'outline'}
                  onClick={() => setImportStatusFilter('owned')}
                  size="sm"
                >
                  Owned
                </Button>
                <Button
                  variant={importStatusFilter === 'wanted' ? 'default' : 'outline'}
                  onClick={() => setImportStatusFilter('wanted')}
                  size="sm"
                >
                  Wanted
                </Button>
              </div>
            </div>

            {duplicateGames.size > 0 && (
              <div className="flex flex-wrap gap-2 items-center">
                <span className="text-sm text-muted-foreground">Show:</span>
                <Button
                  variant={importDuplicateFilter === 'all' ? 'default' : 'outline'}
                  onClick={() => setImportDuplicateFilter('all')}
                  size="sm"
                >
                  All
                </Button>
                <Button
                  variant={importDuplicateFilter === 'new' ? 'default' : 'outline'}
                  onClick={() => setImportDuplicateFilter('new')}
                  size="sm"
                >
                  New Only ({pendingGames.length - duplicateGames.size})
                </Button>
                <Button
                  variant={importDuplicateFilter === 'duplicates' ? 'default' : 'outline'}
                  onClick={() => setImportDuplicateFilter('duplicates')}
                  size="sm"
                  className="text-amber-600 dark:text-amber-500 border-amber-300 dark:border-amber-700 hover:bg-amber-50 dark:hover:bg-amber-950"
                >
                  <Warning className="mr-1" size={16} weight="fill" />
                  Duplicates ({duplicateGames.size})
                </Button>
              </div>
            )}

            <div className="flex flex-wrap gap-2">
              <Button
                variant={importPlatformFilter === 'all' ? 'default' : 'outline'}
                onClick={() => setImportPlatformFilter('all')}
                size="sm"
              >
                All ({importPlatformCounts.all})
              </Button>
              {categories.map((category) => {
                const count = importPlatformCounts[category.id] || 0;
                if (count === 0) return null;
                return (
                  <Button
                    key={category.id}
                    variant={importPlatformFilter === category.id ? 'default' : 'outline'}
                    onClick={() => setImportPlatformFilter(category.id)}
                    size="sm"
                  >
                    {category.name} ({count})
                  </Button>
                );
              })}
            </div>

            <div className="flex justify-between items-center pb-2 border-b">
              <div className="text-sm text-muted-foreground">
                {filteredImportGames.length} {filteredImportGames.length === 1 ? 'game' : 'games'} shown
              </div>
              <div className="flex gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleSelectAllImport}
                >
                  Select All
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleSelectNoneImport}
                >
                  Select None
                </Button>
              </div>
            </div>

            <ScrollArea className="flex-1 -mx-6 px-6">
              <div className="space-y-2 pr-4">
                {filteredImportGames.map((game) => {
                  const category = categories.find(c => c.id === game.platform);
                  const isDuplicate = duplicateGames.has(game.id);
                  return (
                    <div
                      key={game.id}
                      className={`flex items-start gap-3 p-3 border rounded-lg hover:bg-muted/50 transition-colors ${
                        isDuplicate ? 'border-amber-300 dark:border-amber-700 bg-amber-50/50 dark:bg-amber-950/20' : ''
                      }`}
                    >
                      <Checkbox
                        id={`import-game-${game.id}`}
                        checked={selectedGameIds.has(game.id)}
                        onCheckedChange={() => handleToggleGame(game.id)}
                        className="mt-1"
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start gap-2 mb-1">
                          <Label
                            htmlFor={`import-game-${game.id}`}
                            className="font-medium cursor-pointer text-base flex-1"
                          >
                            {game.name}
                          </Label>
                          {isDuplicate && (
                            <Badge variant="outline" className="bg-amber-100 dark:bg-amber-950 text-amber-700 dark:text-amber-400 border-amber-300 dark:border-amber-700 flex items-center gap-1 flex-shrink-0">
                              <Warning size={12} weight="fill" />
                              Duplicate
                            </Badge>
                          )}
                        </div>
                        <div className="flex flex-wrap gap-2 mb-2">
                          {game.acquired ? (
                            <Badge className="bg-primary text-primary-foreground text-xs">Owned</Badge>
                          ) : (
                            <Badge variant="secondary" className="text-xs">Wanted</Badge>
                          )}
                          {game.priority && !game.acquired && (
                            <Badge className="bg-accent text-accent-foreground flex items-center gap-1 text-xs">
                              <Star weight="fill" size={10} />
                              Priority
                            </Badge>
                          )}
                        </div>
                        <div className="text-sm text-muted-foreground space-y-0.5">
                          {!game.acquired && game.targetPrice !== undefined && (
                            <div>Target: ${game.targetPrice.toFixed(2)}</div>
                          )}
                          {game.acquired && game.purchasePrice !== undefined && game.purchasePrice > 0 && (
                            <div>Purchase Price: ${game.purchasePrice.toFixed(2)}</div>
                          )}
                          {game.notes && (
                            <div className="text-xs mt-1 line-clamp-2">{game.notes}</div>
                          )}
                        </div>
                      </div>
                      <div className="flex-shrink-0">
                        <PlatformLogo 
                          platform={game.platform} 
                          size="sm" 
                          logoUrl={category?.logoUrl}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            </ScrollArea>
          </div>

          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setShowImportDialog(false)}>
              Cancel
            </Button>
            <Button onClick={confirmImport} disabled={selectedGameIds.size === 0}>
              <UploadSimple className="mr-2" />
              Import {selectedGameIds.size > 0 && `(${selectedGameIds.size})`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

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
