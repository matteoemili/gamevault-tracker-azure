import { useTheme } from '@/contexts/theme-context';
import { Sun, Moon } from '@phosphor-icons/react';
import { Button } from '@/components/ui/button';

export function DarkModeToggle() {
  const { isDark, toggleDark } = useTheme();

  return (
    <Button
      variant="outline"
      size="icon"
      onClick={toggleDark}
      aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
    >
      {isDark ? <Sun size={16} /> : <Moon size={16} />}
    </Button>
  );
}
