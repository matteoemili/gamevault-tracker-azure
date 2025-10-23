import { Platform, PLATFORM_LOGOS, PLATFORM_NAMES } from '@/lib/types';

interface PlatformLogoProps {
  platform: Platform;
  size?: 'sm' | 'md' | 'lg';
}

const sizeClasses = {
  sm: 'h-4',
  md: 'h-6',
  lg: 'h-8'
};

export function PlatformLogo({ platform, size = 'md' }: PlatformLogoProps) {
  return (
    <img
      src={PLATFORM_LOGOS[platform]}
      alt={PLATFORM_NAMES[platform]}
      className={`${sizeClasses[size]} object-contain`}
      loading="lazy"
    />
  );
}
