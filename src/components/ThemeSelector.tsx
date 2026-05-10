import { useTheme } from '@/contexts/theme-context';
import { THEMES, ThemeName } from '@/lib/themes';
import { Palette } from '@phosphor-icons/react';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';

export function ThemeSelector() {
  const { theme, setTheme } = useTheme();
  const current = THEMES.find(t => t.name === theme);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="gap-2">
          <Palette size={16} />
          <span className="hidden sm:inline">{current?.label ?? 'Theme'}</span>
          <span className="sm:hidden">{current?.emoji}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-52">
        {THEMES.map(t => (
          <DropdownMenuItem
            key={t.name}
            onClick={() => setTheme(t.name as ThemeName)}
            className="flex items-center gap-3 cursor-pointer"
          >
            <span className="text-base">{t.emoji}</span>
            <div className="flex flex-col min-w-0">
              <span className="font-medium text-sm">{t.label}</span>
              <span className="text-xs text-muted-foreground truncate">{t.description}</span>
            </div>
            {theme === t.name && (
              <span className="ml-auto text-primary text-xs font-semibold">✓</span>
            )}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
