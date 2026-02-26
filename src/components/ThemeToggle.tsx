import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { Moon, Sun } from "@phosphor-icons/react";
import { Button } from "@/components/ui/button";

export function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    setIsMounted(true);
  }, []);

  const isDarkMode = resolvedTheme === "dark";
  const nextThemeLabel = isDarkMode ? "Switch to light mode" : "Switch to dark mode";

  return (
    <Button
      variant="outline"
      size="icon"
      onClick={() => setTheme(isDarkMode ? "light" : "dark")}
      aria-label={nextThemeLabel}
      title={nextThemeLabel}
    >
      {isMounted ? (
        isDarkMode ? (
          <Sun aria-hidden="true" className="size-4" />
        ) : (
          <Moon aria-hidden="true" className="size-4" />
        )
      ) : null}
      <span className="sr-only">{nextThemeLabel}</span>
    </Button>
  );
}
