import { act, fireEvent, render, screen } from '@testing-library/react';
import { useState } from 'react';
import { Stepper } from './Stepper';

function Harness() {
  const [v, setV] = useState(175);
  return (
    <>
      <Stepper label="Height" value={v} onChange={setV} step={1} />
      <output data-testid="v">{v}</output>
    </>
  );
}

describe('Stepper hold-to-repeat', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('stops repeating when the pointer is released anywhere', () => {
    render(<Harness />);
    const plus = screen.getByRole('button', { name: 'Increase Height' });
    fireEvent.pointerDown(plus);
    act(() => vi.advanceTimersByTime(1000));
    const during = Number(screen.getByTestId('v').textContent);
    expect(during).toBeGreaterThan(176);
    fireEvent.pointerUp(window);
    act(() => vi.advanceTimersByTime(3000));
    expect(Number(screen.getByTestId('v').textContent)).toBe(during);
  });

  it('a second pointerdown does not orphan the first loop', () => {
    render(<Harness />);
    const plus = screen.getByRole('button', { name: 'Increase Height' });
    fireEvent.pointerDown(plus);
    fireEvent.pointerDown(plus);
    fireEvent.pointerUp(plus);
    const after = Number(screen.getByTestId('v').textContent);
    act(() => vi.advanceTimersByTime(3000));
    expect(Number(screen.getByTestId('v').textContent)).toBe(after);
  });

  it('never runs longer than 6 seconds even if no release event arrives', () => {
    render(<Harness />);
    fireEvent.pointerDown(screen.getByRole('button', { name: 'Increase Height' }));
    act(() => vi.advanceTimersByTime(6500));
    const v = Number(screen.getByTestId('v').textContent);
    act(() => vi.advanceTimersByTime(5000));
    expect(Number(screen.getByTestId('v').textContent)).toBe(v);
  });

  it('a single tap moves by one step', () => {
    render(<Harness />);
    const minus = screen.getByRole('button', { name: 'Decrease Height' });
    fireEvent.pointerDown(minus);
    fireEvent.pointerUp(minus);
    act(() => vi.advanceTimersByTime(2000));
    expect(screen.getByTestId('v').textContent).toBe('174');
  });
});
