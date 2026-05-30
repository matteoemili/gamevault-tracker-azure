import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import { format, isValid } from "date-fns"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Safely format a date string that may be undefined, null, or an empty string.
 * Returns the formatted string when the value is a valid date, or null otherwise.
 * Using null lets callers conditionally render with a simple `&&` guard.
 */
export function formatDate(
  value: string | undefined | null,
  pattern: string
): string | null {
  if (!value) return null;
  const d = new Date(value);
  return isValid(d) ? format(d, pattern) : null;
}
