import { TrendingUp, TrendingDown } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import type { DashboardMetric } from '@/lib/types';
import { cn } from '@/lib/utils';

interface MetricCardProps {
  metric: DashboardMetric;
  icon: React.ElementType;
  accentColor?: string;
}

export function MetricCard({ metric, icon: Icon, accentColor = 'bg-primary/10 text-primary' }: MetricCardProps) {
  const isPositive = (metric.change ?? 0) >= 0;
  const displayValue =
    typeof metric.value === 'number'
      ? `${metric.prefix ?? ''}${metric.value.toLocaleString()}${metric.suffix ?? ''}`
      : metric.value;

  return (
    <Card className="border-border/60 bg-card hover:shadow-md transition-shadow duration-200">
      <CardContent className="p-5">
        <div className="flex items-start justify-between mb-3">
          <div className={cn('flex h-9 w-9 items-center justify-center rounded-lg', accentColor)}>
            <Icon className="h-4.5 w-4.5" />
          </div>
          {metric.change !== undefined && (
            <div
              className={cn(
                'flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
                isPositive
                  ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400'
                  : 'bg-red-500/10 text-red-600 dark:text-red-400'
              )}
            >
              {isPositive ? (
                <TrendingUp className="h-3 w-3" />
              ) : (
                <TrendingDown className="h-3 w-3" />
              )}
              {Math.abs(metric.change)}%
            </div>
          )}
        </div>
        <div
          className="text-2xl font-bold text-foreground mb-1 tabular-nums"
          style={{ fontFamily: "'Playfair Display', Georgia, serif" }}
        >
          {displayValue}
        </div>
        <p className="text-xs font-medium text-muted-foreground">{metric.label}</p>
        {metric.changeLabel && (
          <p className="text-[10px] text-muted-foreground/70 mt-0.5">{metric.changeLabel}</p>
        )}
      </CardContent>
    </Card>
  );
}
