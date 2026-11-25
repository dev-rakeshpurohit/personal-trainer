import { lazy, Suspense, type ReactNode } from 'react';
import { createBrowserRouter, Navigate } from 'react-router-dom';
import { RootLayout, TabLayout } from './app/Layout';
import { RouteError } from './app/RouteError';
import Today from './features/today/Today';
import Train from './features/train/Train';
import Eat from './features/eat/Eat';
import More from './features/more/More';
import Onboarding from './features/onboarding/Onboarding';
import Library from './features/library/Library';
import Player from './features/workout/Player';
import Prestart from './features/workout/Prestart';
import Summary from './features/workout/Summary';

// Heavier, less-used screens are code-split (charts, editor, dev tools)
const Progress = lazy(() => import('./features/progress/Progress'));
const ExerciseDetail = lazy(() => import('./features/library/ExerciseDetail'));
const History = lazy(() => import('./features/history/History'));
const DayDetail = lazy(() => import('./features/history/DayDetail'));
const Developer = lazy(() => import('./features/settings/Developer'));

const L = (el: ReactNode) => (
  <Suspense fallback={<div className="flex h-40 items-center justify-center text-muted" aria-busy="true">Loading…</div>}>{el}</Suspense>
);

export const router: ReturnType<typeof createBrowserRouter> = createBrowserRouter([
  {
    element: <RootLayout />,
    errorElement: <RouteError />,
    children: [
      {
        element: <TabLayout />,
        errorElement: <RouteError />,
        children: [
          { path: '/', element: <Navigate to="/today" replace /> },
          { path: '/today', element: <Today /> },
          { path: '/train', element: <Train /> },
          { path: '/train/library', element: <Library /> },
          { path: '/train/library/:exerciseId', element: L(<ExerciseDetail />) },
          { path: '/train/history', element: L(<History />) },
          { path: '/train/history/:dayKey', element: L(<DayDetail />) },
          { path: '/eat', element: <Eat /> },
          { path: '/progress', element: L(<Progress />) },
          { path: '/more', element: <More /> },
          { path: '/more/dev', element: L(<Developer />) },
        ],
      },
      { path: '/onboarding', element: <Onboarding /> },
      { path: '/workout', element: <Player /> },
      { path: '/workout/today', element: <Prestart /> },
      { path: '/workout/start/:dayId', element: <Prestart /> },
      { path: '/workout/summary/:sessionId', element: <Summary /> },
      { path: '*', element: <Navigate to="/today" replace /> },
    ],
  },
]);
