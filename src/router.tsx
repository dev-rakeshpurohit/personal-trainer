import { createBrowserRouter, Navigate } from 'react-router-dom';
import { RootLayout, TabLayout } from './app/Layout';
import Today from './features/today/Today';
import Train from './features/train/Train';
import Eat from './features/eat/Eat';
import Progress from './features/progress/Progress';
import More from './features/more/More';
import Onboarding from './features/onboarding/Onboarding';
import Library from './features/library/Library';
import ExerciseDetail from './features/library/ExerciseDetail';
import Player from './features/workout/Player';
import Prestart from './features/workout/Prestart';
import Summary from './features/workout/Summary';

export const router: ReturnType<typeof createBrowserRouter> = createBrowserRouter([
  {
    element: <RootLayout />,
    children: [
      {
        element: <TabLayout />,
        children: [
          { path: '/', element: <Navigate to="/today" replace /> },
          { path: '/today', element: <Today /> },
          { path: '/train', element: <Train /> },
          { path: '/train/library', element: <Library /> },
          { path: '/train/library/:exerciseId', element: <ExerciseDetail /> },
          { path: '/eat', element: <Eat /> },
          { path: '/progress', element: <Progress /> },
          { path: '/more', element: <More /> },
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
