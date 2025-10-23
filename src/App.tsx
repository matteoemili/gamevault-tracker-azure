import { useState, useMemo } from 'react';
import { useKV } from '@github/spark/hooks';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Game, Platform, PLATFORM_NAMES } from '@/lib/types';
import { GameCard } from '@/components/GameCard';
import { GameDialog } from '@/components/GameDialog';
import { ImportExportMenu } from '@/components/ImportExportMenu';
import { Plus, MagnifyingGlass, FunnelSimple } from '@phosphor-icons/react';
import { Toaster } from '@/components/ui/sonner';
import { toast } from 'sonner';

type StatusFilter = 'all' | 'owned' | 'wanted' | 'priority';

function App() {
  const [games, setGames] = useKV<Game[]>('game-collection', []);
  const [searchQuery, setSearchQuery] = useState('');
  const [platformFilter, setPlatformFilter] = useState<Platform | 'all'>('all');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingGame, setEditingGame] = useState<Game | undefined>();

  const filteredGames = useMemo(() => {
    if (!games) return [];
    return games.filter(game => {
      const matchesSearch = game.name.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesPlatform = platformFilter === 'all' || game.platform === platformFilter;
      
      let matchesStatus = true;
      if (statusFilter === 'owned') {
        matchesStatus = game.acquired;
      } else if (statusFilter === 'wanted') {
        matchesStatus = !game.acquired;
      } else if (statusFilter === 'priority') {
        matchesStatus = !game.acquired && game.priority === true;
      }
      
      return matchesSearch && matchesPlatform && matchesStatus;
    });
  }, [games, searchQuery, platformFilter, statusFilter]);

  const handleSaveGame = (game: Game) => {
    setGames(currentGames => {
      const current = currentGames || [];
      const existingIndex = current.findIndex(g => g.id === game.id);
      if (existingIndex >= 0) {
        const updated = [...current];
        updated[existingIndex] = game;
        return updated;
      }
      return [...current, game];
    });
    
    toast.success(editingGame ? 'Game updated' : 'Game added');
    setEditingGame(undefined);
  };

  const handleEditGame = (game: Game) => {
    setEditingGame(game);
    setDialogOpen(true);
  };

  const handleDeleteGame = (id: string) => {
    setGames(currentGames => (currentGames || []).filter(g => g.id !== id));
    toast.success('Game deleted');
  };

  const handleAddNew = () => {
    setEditingGame(undefined);
    setDialogOpen(true);
  };

  const handleImport = (importedGames: Game[]) => {
    setGames(currentGames => [...(currentGames || []), ...importedGames]);
  };

  const handleDialogClose = (open: boolean) => {
    setDialogOpen(open);
    if (!open) {
      setEditingGame(undefined);
    }
  };

  const platformCounts = useMemo(() => {
    const counts: Record<Platform | 'all', number> = {
      all: games?.length || 0,
      PS1: 0,
      PS2: 0,
      PS3: 0,
      PSP: 0,
      PC: 0
    };
    
    games?.forEach(game => {
      counts[game.platform]++;
    });
    
    return counts;
  }, [games]);

  return (
    <div className="min-h-screen bg-background">
      <Toaster />
      
      <div className="container mx-auto px-4 py-8 max-w-7xl">
        <header className="mb-8">
          <div className="flex items-center justify-between mb-6">
            <h1 className="text-4xl font-bold tracking-tight">Video Game Collection</h1>
            <div className="flex gap-2">
              <ImportExportMenu games={games || []} onImport={handleImport} />
              <Button onClick={handleAddNew}>
                <Plus className="mr-2" />
                Add Game
              </Button>
            </div>
          </div>

          <div className="flex flex-col gap-4">
            <div className="flex flex-col sm:flex-row gap-4">
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <Input
                  placeholder="Search games..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-10"
                />
              </div>
              
              <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as StatusFilter)}>
                <SelectTrigger className="w-full sm:w-48">
                  <FunnelSimple className="mr-2" />
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Games</SelectItem>
                  <SelectItem value="owned">Owned</SelectItem>
                  <SelectItem value="wanted">Wanted</SelectItem>
                  <SelectItem value="priority">Priority</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                variant={platformFilter === 'all' ? 'default' : 'outline'}
                onClick={() => setPlatformFilter('all')}
                size="sm"
              >
                All ({platformCounts.all})
              </Button>
              {Object.entries(PLATFORM_NAMES).map(([key, name]) => (
                <Button
                  key={key}
                  variant={platformFilter === key ? 'default' : 'outline'}
                  onClick={() => setPlatformFilter(key as Platform)}
                  size="sm"
                >
                  {name} ({platformCounts[key as Platform]})
                </Button>
              ))}
            </div>
          </div>
        </header>

        <main>
          {filteredGames.length === 0 ? (
            <div className="text-center py-16">
              {(games?.length || 0) === 0 ? (
                <div className="max-w-md mx-auto">
                  <h2 className="text-2xl font-semibold mb-2">Start Your Collection</h2>
                  <p className="text-muted-foreground mb-6">
                    Add games to track your collection, wishlist, and purchases.
                  </p>
                  <Button onClick={handleAddNew} size="lg">
                    <Plus className="mr-2" />
                    Add Your First Game
                  </Button>
                </div>
              ) : (
                <div className="max-w-md mx-auto">
                  <h2 className="text-2xl font-semibold mb-2">No Games Found</h2>
                  <p className="text-muted-foreground mb-6">
                    Try adjusting your filters or search query.
                  </p>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setSearchQuery('');
                      setPlatformFilter('all');
                      setStatusFilter('all');
                    }}
                  >
                    Clear Filters
                  </Button>
                </div>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              {filteredGames.map(game => (
                <GameCard
                  key={game.id}
                  game={game}
                  onEdit={handleEditGame}
                  onDelete={handleDeleteGame}
                />
              ))}
            </div>
          )}
        </main>
      </div>

      <GameDialog
        open={dialogOpen}
        onOpenChange={handleDialogClose}
        onSave={handleSaveGame}
        game={editingGame}
      />
    </div>
  );
}

export default App;
