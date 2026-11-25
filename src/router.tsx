import { createBrowserRouter, Navigate } from 'react-router-dom';
import { RootLayout, TabLayout } from './app/Layout';
import Today from './features/today/Today';
import Train from './features/train/Train';
import Eat from './features/eat/Eat';
import Progress from './features/progress/Progress';
import More from './features/more/More';
import Onboarding from './features/onboarding/Onboarding';

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
          { path: '/eat', element: <Eat /> },
          { path: '/progress', element: <Progress /> },
          { path: '/more', element: <More /> },
        ],
      },
      { path: '/onboarding', element: <Onboarding /> },
      { path: '*', element: <Navigate to="/today" replace /> },
    ],
  },
]);
