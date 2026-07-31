# Visual Regression Baselines

FiliusPad uses Swift-to-Swift visual baselines as a regression safety net. Java screenshots remain reference boards for concept continuity; they are not pixel-diff targets.

## Canonical configuration

- iPad (A16) simulator
- landscape-left orientation
- light appearance
- English locale
- deterministic UI-test-created topology and runtime state
- similarity threshold: `0.94`

The suite covers the empty editor, a connected populated editor, the device inspector, the simulation desktop, Software Manager, the command prompt, and the packet viewer. Runtime assertions also verify that the device desktop occupies nearly the full iPad window and that CMD retains its prompt, transcript, window controls, and taskbar. Semantic assertions run with each screenshot so a high visual similarity cannot hide missing controls or incorrect state.

## Run the gate

From the repository root on the development Mac:

```bash
ios/scripts/run-visual-regression.sh
```

The result bundle defaults to `ios/build/visual-regression.xcresult`. Expected, actual, and difference PNG attachments are retained for failures.

## Intentionally update baselines

Only update baselines after reviewing the UI change in the simulator:

```bash
ios/scripts/run-visual-regression.sh --record
git diff -- ios/FiliusPadUITests/ParityBaselines
```

The normal comparison command never overwrites baseline files. Review every changed image before committing it. A baseline change should be in the same commit as the intentional visual change or in a dedicated, clearly explained baseline commit immediately after it.

## Expanding coverage

Add a baseline when a change introduces a materially different surface, supported width, locale, or accessibility text-size layout. Avoid multiplying screenshots for states that are already covered by semantic assertions.
