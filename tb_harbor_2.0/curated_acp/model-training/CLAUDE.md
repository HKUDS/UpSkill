# Model Training — PyTorch Model Reconstruction & Output-Layer Fine-Tuning

## Task Pattern
Given `/app/weights.pt` (state dict) + `/app/dataset.pt`, produce `/app/model.pt` (TorchScript) with improved MSE by tuning only `output_layer`.

**Core constraint:** Only `output_layer.*` weights may differ from the original state dict. All other layers stay frozen.

---

## Phase 1 — Inspect the State Dict (NEVER GUESS)

```python
import torch
sd = torch.load('/app/weights.pt', map_location='cpu', weights_only=True)
for k, v in sd.items():
    print(f"{k:50s} | shape={str(list(v.shape)):25s} | dtype={v.dtype}")
```

The keys and shapes are the single source of truth for the architecture.

## Phase 2 — Map Keys to Layer Types

| Key pattern | Layer type | Dimension notes |
|---|---|---|
| `.weight` + `.bias` only | `nn.Linear` | `out=shape[0]`, `in=shape[1]` |
| `.weight` only, 2D | `nn.Embedding` | `vocab=shape[0]`, `dim=shape[1]` |
| `.weight` + `.bias`, both 1D | `nn.LayerNorm` | `norm_shape=len(weight)` |
| Above + `.running_mean` + `.running_var` | `nn.BatchNorm1d/2d` | `num_features` from shape |
| `in_proj_weight` + `out_proj_weight` + biases | `nn.MultiheadAttention` | `embed_dim` from shape math |
| `weight_ih_l0` + `weight_hh_l0` + biases | `nn.LSTM`/`GRU`/`RNN` | Check bias count for type |

## Phase 3 — Build `RecoveredModel`

- Class name **must** be `RecoveredModel`
- `__init__` attribute names **must** match state dict key prefixes exactly
- Use `nn.Sequential`/`nn.ModuleList` only for indexed keys (`layers.0.weight`, …)
- Implement `forward(self, x)` matching the architecture
- Verify with `model.load_state_dict(sd)` — must succeed with no errors

## Phase 4 — Compute Baseline MSE

```python
data = torch.load('/app/dataset.pt', map_location='cpu', weights_only=True)
# Check format: print(type(data)); if dict: print(data.keys())
# Extract inputs/targets accordingly

model.eval()
with torch.no_grad():
    baseline_mse = nn.MSELoss()(model(inputs), targets).item()
```

**Important:** `model.eval()` before inference (Dropout/BatchNorm behave differently in train mode).

## Phase 5 — Freeze & Tune Only `output_layer`

```python
# Freeze all
for p in model.parameters():
    p.requires_grad = False
# Unfreeze only output_layer
for n, p in model.named_parameters():
    if 'output_layer' in n:
        p.requires_grad = True

optimizer = torch.optim.Adam(
    [p for n, p in model.named_parameters() if 'output_layer' in n], lr=0.01
)
criterion = nn.MSELoss()

model.train()
for epoch in range(1000):
    optimizer.zero_grad()
    loss = criterion(model(inputs), targets)
    loss.backward()
    optimizer.step()
    if loss.item() < baseline_mse * 0.95:  # early stop at 5% improvement
        break
```

Verify: `new_mse < baseline_mse` must pass.

## Phase 6 — Save as TorchScript

```python
torch.jit.script(model).save('/app/model.pt')
```

Prefer `torch.jit.script()` over `torch.jit.trace()` — it handles control flow and is less brittle. Verify by reloading: `torch.jit.load('/app/model.pt')`.

## Common Pitfalls

1. **Module name mismatch** — `load_state_dict` fails with missing/unexpected keys. Print both sets and align `__init__` names.
2. **Wrong layer type** — A 1D weight could be `LayerNorm` or bias-less `Linear`; check for paired bias key.
3. **Missing `model.eval()`** before baseline — Dropout/BatchNorm differ in train vs eval.
4. **Dataset format** — `/app/dataset.pt` may be a dict `{'inputs': ..., 'targets': ...}` or a tuple `(inputs, targets)`. Inspect first.
5. **TorchScript failures** — If `script()` fails, try wrapping forward logic more explicitly.
