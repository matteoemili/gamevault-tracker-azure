import { Platform, PLATFORM_LOGOS } from '@/lib/types';

interface PlatformLogoProps {
  platform: Platform;
  size?: 'sm' | 'md' | 'lg';
  logoUrl?: string;
}

const sizeClasses = {
  sm: 'h-4',
  md: 'h-6',
  lg: 'h-8'
};

export function PlatformLogo({ platform, size = 'md', logoUrl }: PlatformLogoProps) {
  const src = logoUrl || PLATFORM_LOGOS[platform] || '';
  const alt = platform;
  
  return (
    <img
      src={src}
      alt={alt}
      className={`${sizeClasses[size]} object-contain`}
      loading="lazy"
      onError={(e) => {
        (e.target as HTMLImageElement).src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="24" height="24"%3E%3Crect fill="%23ccc" width="24" height="24"/%3E%3C/svg%3E';
      }}
    />
  );
}
