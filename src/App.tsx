import { useState, useMemo } from 'react';
import { useAzureTableList } from '@/hooks/use-azure-table';
import { getAzureConfig } from '@/lib/azure-config';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Game, Platform } from '@/lib/types';
import { GameCard } from '@/components/GameCard';
import { GameDialog } from '@/components/GameDialog';
import { ImportExportMenu } from '@/components/ImportExportMenu';
import { PlatformCategory } from '@/components/CategoryDialog';
import { DEFAULT_CATEGORIES } from '@/lib/categories';
import { Plus, MagnifyingGlass, FunnelSimple } from '@phosphor-icons/react';
import { Toaster } from '@/components/ui/sonner';
import { toast } from 'sonner';
import { ThemeSelector } from '@/components/ThemeSelector';
import { DarkModeToggle } from '@/components/DarkModeToggle';
import { useTheme } from '@/contexts/theme-context';

type StatusFilter = 'all' | 'owned' | 'wanted' | 'priority';

function App() {
  const azureConfig = getAzureConfig();
  const { theme } = useTheme();
  const [games, setGames, gamesLoading] = useAzureTableList<Game>(azureConfig.tables.games, []);
  const [categories, setCategories, categoriesLoading] = useAzureTableList<PlatformCategory>(azureConfig.tables.categories, DEFAULT_CATEGORIES);
  const [searchQuery, setSearchQuery] = useState('');
  const [platformFilter, setPlatformFilter] = useState<Platform | 'all'>('all');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingGame, setEditingGame] = useState<Game | undefined>();

  const filteredGames = useMemo(() => {
    if (!games) return [];
    return games
      .filter(game => {
        const matchesSearch = game.name.toLowerCase().includes(searchQuery.toLowerCase());
        const matchesPlatform = platformFilter === 'all' || game.platform === platformFilter;
        let matchesStatus = true;
        if (statusFilter === 'owned') matchesStatus = game.acquired;
        else if (statusFilter === 'wanted') matchesStatus = !game.acquired;
        else if (statusFilter === 'priority') matchesStatus = !game.acquired && game.priority === true;
        return matchesSearch && matchesPlatform && matchesStatus;
      })
      .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  }, [games, searchQuery, platformFilter, statusFilter]);

  const handleSaveGame = (game: Game) => {
    setGames(current => {
      const arr = current || [];
      const idx = arr.findIndex(g => g.id === game.id);
      if (idx >= 0) { const u = [...arr]; u[idx] = game; return u; }
      return [...arr, game];
    });
    toast.success(editingGame ? 'Game updated' : 'Game added');
    setEditingGame(undefined);
  };

  const handleEditGame = (game: Game) => { setEditingGame(game); setDialogOpen(true); };
  const handleDeleteGame = (id: string) => { setGames(c => (c || []).filter(g => g.id !== id)); toast.success('Game deleted'); };
  const handleAddNew = () => { setEditingGame(undefined); setDialogOpen(true); };
  const handleImport = (imported: Game[]) => setGames(c => [...(c || []), ...imported]);
  const handleCategoriesChange = (nc: PlatformCategory[]) => { setCategories(nc); toast.success('Categories updated'); };
  const handleDialogClose = (open: boolean) => { setDialogOpen(open); if (!open) setEditingGame(undefined); };

  const platformCounts = useMemo(() => {
    const counts: Record<string, number> = { all: games?.length || 0 };
    (categories || DEFAULT_CATEGORIES).forEach(c => { counts[c.id] = 0; });
    games?.forEach(g => { if (counts[g.platform] !== undefined) counts[g.platform]++; });
    return counts;
  }, [games, categories]);

  const stats = useMemo(() => {
    const all = games || [];
    return {
      total: all.length,
      owned: all.filter(g => g.acquired).length,
      wanted: all.filter(g => !g.acquired).length,
      priority: all.filter(g => !g.acquired && g.priority).length,
    };
  }, [games]);

  const catList = categories || DEFAULT_CATEGORIES;

  const gridClass = theme === 'dashboard-pro'
    ? 'grid grid-cols-1 lg:grid-cols-2 gap-2'
    : 'grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4';  return (
    <div className="min-h-screen bg-background">
      <Toaster />

      {/* ── NEON ARCADE HEADER ── */}
      {theme === 'neon-arcade' && (
        <header style={{ borderBottom: '1px solid rgba(167,139,250,0.2)', background: 'rgba(15,13,26,0.95)', backdropFilter: 'blur(8px)' }}>
          <div className="container mx-auto px-4 py-5 max-w-7xl">
            <div className="flex items-center justify-between mb-4">
              <div>
                <div className="font-mono text-xs mb-1" style={{ color: 'rgba(167,139,250,0.5)' }}>// GAMEVAULT v2.0 SYSTEM ONLINE</div>
                <h1 className="font-mono font-black text-2xl tracking-wide"
                  style={{ background: 'linear-gradient(90deg, #a78bfa, #38bdf8)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
                  GAME_VAULT.EXE
                </h1>
              </div>
              <div className="flex items-center gap-2">
                <ThemeSelector />
                <DarkModeToggle />
                <ImportExportMenu games={games || []} onImport={handleImport} categories={catList} onCategoriesChange={handleCategoriesChange} />
                <Button onClick={handleAddNew} size="sm" className="font-mono text-xs">
                  <Plus size={12} className="mr-1" /> INSERT
                </Button>
              </div>
            </div>
            {stats.total > 0 && (
              <div className="font-mono text-xs mb-4 flex gap-4" style={{ color: 'var(--muted-foreground)' }}>
                <span>TOTAL: <span style={{ color: '#a78bfa' }}>{stats.total}</span></span>
                <span>OWNED: <span style={{ color: '#4ade80' }}>{stats.owned}</span></span>
                <span>HUNTING: <span style={{ color: '#a78bfa' }}>{stats.wanted}</span></span>
                {stats.priority > 0 && <span>PRIORITY: <span style={{ color: '#fb923c' }}>{stats.priority}</span></span>}
              </div>
            )}
            <div className="flex flex-col sm:flex-row gap-2">
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2" size={14} style={{ color: 'var(--muted-foreground)' }} />
                <Input placeholder="SEARCH_QUERY..." value={searchQuery} onChange={e => setSearchQuery(e.target.value)} className="pl-9" />
              </div>
              <Select value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
                <SelectTrigger className="w-full sm:w-44"><FunnelSimple size={14} className="mr-2" /><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">ALL</SelectItem>
                  <SelectItem value="owned">ACQUIRED</SelectItem>
                  <SelectItem value="wanted">HUNTING</SelectItem>
                  <SelectItem value="priority">PRIORITY</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-wrap gap-1.5 mt-3">
              {[{ id: 'all', name: 'ALL' }, ...catList.map(c => ({ id: c.id, name: c.name.toUpperCase() }))].map(p => (
                <Button key={p.id} variant={platformFilter === p.id ? 'default' : 'outline'} onClick={() => setPlatformFilter(p.id as Platform | 'all')} size="sm"
                  className="font-mono text-xs h-7 px-3">
                  [{p.name}] ({platformCounts[p.id] ?? 0})
                </Button>
              ))}
            </div>
          </div>
        </header>
      )}

      {/* ── CLEAN MINIMAL HEADER ── */}
      {theme === 'clean-minimal' && (
        <header style={{ borderBottom: '1px solid var(--border)' }}>
          <div className="container mx-auto px-6 py-6 max-w-7xl">
            <div className="flex items-end justify-between mb-6">
              <div>
                <p className="text-xs font-medium uppercase tracking-widest text-muted-foreground mb-1">Personal Collection</p>
                <h1 className="text-3xl font-bold tracking-tight">Game Vault</h1>
              </div>
              <div className="flex items-center gap-2">
                <ThemeSelector />
                <DarkModeToggle />
                <ImportExportMenu games={games || []} onImport={handleImport} categories={catList} onCategoriesChange={handleCategoriesChange} />
                <Button onClick={handleAddNew}><Plus size={16} className="mr-1.5" /> Add Game</Button>
              </div>
            </div>
            {stats.total > 0 && (
              <div className="stats-bar mb-5">
                <span className="stats-bar-item"><span className="stats-bar-dot" style={{ background: '#6366f1' }} />{stats.total} games</span>
                <span className="stats-bar-item"><span className="stats-bar-dot" style={{ background: '#22c55e' }} />{stats.owned} owned</span>
                <span className="stats-bar-item"><span className="stats-bar-dot" style={{ background: '#a78bfa' }} />{stats.wanted} wishlist</span>
                {stats.priority > 0 && <span className="stats-bar-item"><span className="stats-bar-dot" style={{ background: '#f59e0b' }} />{stats.priority} priority</span>}
              </div>
            )}
            <div className="flex flex-col sm:flex-row gap-3">
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" size={15} />
                <Input placeholder="Search your collection…" value={searchQuery} onChange={e => setSearchQuery(e.target.value)} className="pl-10" />
              </div>
              <Select value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
                <SelectTrigger className="w-full sm:w-44"><FunnelSimple size={15} className="mr-2" /><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All games</SelectItem>
                  <SelectItem value="owned">Owned</SelectItem>
                  <SelectItem value="wanted">Wishlist</SelectItem>
                  <SelectItem value="priority">Priority</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-wrap gap-2 mt-4">
              {[{ id: 'all', name: 'All' }, ...catList].map(p => (
                <Button key={'id' in p ? p.id : ''} variant={platformFilter === ('id' in p ? p.id : '') ? 'default' : 'ghost'}
                  onClick={() => setPlatformFilter(('id' in p ? p.id : 'all') as Platform | 'all')} size="sm"
                  className="rounded-full text-xs h-7 px-4">
                  {'name' in p ? p.name : 'All'} {platformCounts[('id' in p ? p.id : 'all')] ?? 0}
                </Button>
              ))}
            </div>
          </div>
        </header>
      )}

      {/* ── RETRO COLLECTOR HEADER ── */}
      {theme === 'retro-collector' && (
        <header style={{ background: '#f5edd8', borderBottom: '3px double #c5a572' }}>
          <div className="container mx-auto px-6 py-6 max-w-7xl">
            <div className="text-center mb-5" style={{ borderBottom: '1px dashed #c5a572', paddingBottom: '16px' }}>
              <p className="text-xs uppercase tracking-widest font-bold mb-1" style={{ color: 'var(--primary)', fontFamily: 'ui-monospace, monospace' }}>Personal Registry</p>
              <h1 className="text-4xl font-black tracking-tight" style={{ fontFamily: 'Georgia, serif', color: 'var(--foreground)' }}>The Game Vault</h1>
              <p className="text-sm mt-1" style={{ color: 'var(--muted-foreground)', fontFamily: 'Georgia, serif', fontStyle: 'italic' }}>A collector's personal ledger</p>
            </div>
            <div className="flex items-center justify-between mb-4">
              <div className="stats-bar">
                {stats.total > 0 && <>
                  <span className="stats-bar-item" style={{ fontFamily: 'Georgia, serif' }}>
                    <span className="stats-bar-dot" style={{ background: '#b45309' }} />
                    {stats.total} entries
                  </span>
                  <span className="stats-bar-item" style={{ fontFamily: 'Georgia, serif' }}>
                    <span className="stats-bar-dot" style={{ background: '#166534' }} />
                    {stats.owned} owned
                  </span>
                  <span className="stats-bar-item" style={{ fontFamily: 'Georgia, serif' }}>
                    <span className="stats-bar-dot" style={{ background: '#92400e' }} />
                    {stats.wanted} wanted
                  </span>
                </>}
              </div>
              <div className="flex items-center gap-2">
                <ThemeSelector />
                <DarkModeToggle />
                <ImportExportMenu games={games || []} onImport={handleImport} categories={catList} onCategoriesChange={handleCategoriesChange} />
                <Button onClick={handleAddNew} size="sm">
                  <Plus size={14} className="mr-1" /> Add Entry
                </Button>
              </div>
            </div>
            <div className="flex flex-col sm:flex-row gap-3">
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2" size={14} style={{ color: 'var(--muted-foreground)' }} />
                <Input placeholder="Search entries…" value={searchQuery} onChange={e => setSearchQuery(e.target.value)} className="pl-10" />
              </div>
              <Select value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
                <SelectTrigger className="w-full sm:w-44"><FunnelSimple size={14} className="mr-2" /><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Entries</SelectItem>
                  <SelectItem value="owned">Owned</SelectItem>
                  <SelectItem value="wanted">Wanted</SelectItem>
                  <SelectItem value="priority">Priority</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-wrap gap-2 mt-3">
              <Button variant={platformFilter === 'all' ? 'default' : 'outline'} onClick={() => setPlatformFilter('all')} size="sm">
                All ({platformCounts.all})
              </Button>
              {catList.map(c => (
                <Button key={c.id} variant={platformFilter === c.id ? 'default' : 'outline'} onClick={() => setPlatformFilter(c.id as Platform)} size="sm">
                  {c.name} ({platformCounts[c.id] || 0})
                </Button>
              ))}
            </div>
          </div>
        </header>
      )}

      {/* ── DASHBOARD PRO HEADER ── */}
      {theme === 'dashboard-pro' && (
        <header style={{ borderBottom: '1px solid var(--border)', background: 'var(--background)' }}>
          <div className="container mx-auto px-4 py-3 max-w-7xl">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <h1 className="text-base font-semibold">GameVault</h1>
                    <span className="text-xs px-1.5 py-0.5 rounded font-mono" style={{ background: 'var(--muted)', color: 'var(--muted-foreground)' }}>v2</span>
                  </div>
                  {stats.total > 0 && (
                    <div className="flex items-center gap-3 mt-0.5">
                      <span className="text-xs font-mono" style={{ color: 'var(--muted-foreground)' }}>{stats.total} games</span>
                      <span className="text-xs font-mono" style={{ color: '#10b981' }}>●&nbsp;{stats.owned} owned</span>
                      <span className="text-xs font-mono" style={{ color: '#f59e0b' }}>●&nbsp;{stats.wanted} wanted</span>
                      {stats.priority > 0 && <span className="text-xs font-mono" style={{ color: '#ef4444' }}>●&nbsp;{stats.priority} priority</span>}
                    </div>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-1.5">
                <ThemeSelector />
                <DarkModeToggle />
                <ImportExportMenu games={games || []} onImport={handleImport} categories={catList} onCategoriesChange={handleCategoriesChange} />
                <Button onClick={handleAddNew} size="sm" className="h-7 text-xs px-3">
                  <Plus size={12} className="mr-1" /> New
                </Button>
              </div>
            </div>
          </div>
          <div style={{ borderTop: '1px solid var(--border)' }}>
            <div className="container mx-auto px-4 py-2 max-w-7xl">
              <div className="flex flex-col sm:flex-row gap-2">
                <div className="relative flex-1">
                  <MagnifyingGlass className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" size={13} />
                  <Input placeholder="Filter games…" value={searchQuery} onChange={e => setSearchQuery(e.target.value)} className="pl-8 h-7 text-xs" />
                </div>
                <Select value={statusFilter} onValueChange={v => setStatusFilter(v as StatusFilter)}>
                  <SelectTrigger className="w-full sm:w-36 h-7 text-xs"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All</SelectItem>
                    <SelectItem value="owned">Owned</SelectItem>
                    <SelectItem value="wanted">Wanted</SelectItem>
                    <SelectItem value="priority">Priority</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={platformFilter} onValueChange={v => setPlatformFilter(v as Platform | 'all')}>
                  <SelectTrigger className="w-full sm:w-36 h-7 text-xs"><SelectValue placeholder="Platform" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All platforms</SelectItem>
                    {catList.map(c => <SelectItem key={c.id} value={c.id}>{c.name} ({platformCounts[c.id] || 0})</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
        </header>
      )}

      {/* ── MAIN CONTENT ── */}
      <main className="container mx-auto px-4 max-w-7xl" style={{
        paddingTop: '24px',
        paddingBottom: '48px',
      }}>
        {filteredGames.length === 0 ? (
          <div className="text-center py-20">
            {(games?.length || 0) === 0 ? (
              <div className="max-w-sm mx-auto">
                <div className="text-5xl mb-4">{theme === 'neon-arcade' ? '⬛' : theme === 'retro-collector' ? '📦' : '📭'}</div>
                <h2 className="text-xl font-semibold mb-2">
                  {theme === 'neon-arcade' ? 'VAULT EMPTY' : theme === 'retro-collector' ? 'No Entries Yet' : 'Start Your Collection'}
                </h2>
                <p className="text-muted-foreground mb-6 text-sm">
                  {theme === 'neon-arcade' ? '// Add your first game to begin tracking' : 'Add games to track your collection, wishlist, and purchases.'}
                </p>
                <Button onClick={handleAddNew} size="lg">
                  <Plus size={18} className="mr-2" />
                  {theme === 'neon-arcade' ? 'INSERT FIRST ENTRY' : theme === 'retro-collector' ? 'Record First Entry' : 'Add Your First Game'}
                </Button>
              </div>
            ) : (
              <div className="max-w-sm mx-auto">
                <div className="text-5xl mb-4">🔍</div>
                <h2 className="text-xl font-semibold mb-2">No matches found</h2>
                <p className="text-muted-foreground mb-6 text-sm">Try adjusting your filters or search query.</p>
                <Button variant="outline" onClick={() => { setSearchQuery(''); setPlatformFilter('all'); setStatusFilter('all'); }}>
                  Clear Filters
                </Button>
              </div>
            )}
          </div>
        ) : (
          <div className={gridClass}>
            {filteredGames.map(game => (
              <GameCard
                key={game.id}
                game={game}
                onEdit={handleEditGame}
                onDelete={handleDeleteGame}
                categories={catList}
              />
            ))}
          </div>
        )}
      </main>

      <GameDialog open={dialogOpen} onOpenChange={handleDialogClose} onSave={handleSaveGame} game={editingGame} categories={catList} />
    </div>
  );
}

export default App;
