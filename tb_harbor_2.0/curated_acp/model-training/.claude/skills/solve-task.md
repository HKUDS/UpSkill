# Solve: Reconstruct Model → Freeze → Tune Output Layer → Save TorchScript

Ordered checklist: given `/app/weights.pt` + `/app/dataset.pt`, produce `/app/model.pt` with improved MSE by tuning only `output_layer`.

---

## 1. Discover the Architecture (NEVER GUESS)

```python
import torch
sd = torch.load('/app/weights.pt', map_location='cpu', weights_only=True)
for k, v in sd.items():
    print(f"{k:50s} | {str(list(v.shape)):25s} | {v.dtype}")
```

- [ ] All keys printed — full layer hierarchy visible

**Classify each key prefix:**
- `Linear` — `.weight` + `.bias` (or `.weight` only if bias=False)
- `Embedding` — `.weight` only, 2D (vocab, dim)
- `LayerNorm` — `.weight` + `.bias`, both 1D
- `BatchNorm` — above + `.running_mean` + `.running_var`
- `MultiheadAttention` — `in_proj_weight`, `out_proj_weight`, etc.
- `LSTM`/`GRU`/`RNN` — `weight_ih_l0`, `weight_hh_l0`, `bias_ih_l0`, `bias_hh_l0`

**Extract dimensions:** Linear: `out=shape[0], in=shape[1]`. Embedding: `vocab=shape[0], dim=shape[1]`. LayerNorm: `norm_shape=len(weight)`.

---

## 2. Build `RecoveredModel(nn.Module)`

- [ ] Class name is exactly `RecoveredModel`
- [ ] `__init__` attribute names match state dict key prefixes exactly
- [ ] Use `nn.Sequential`/`nn.ModuleList` only for indexed keys (`layers.0.weight`, …)
- [ ] `forward(self, x)` implements the data flow implied by the architecture

```python
model = RecoveredModel()
model.load_state_dict(sd)  # Must succeed with NO errors
```

- [ ] Fix "Missing key(s)" → attribute name mismatch; "Unexpected key(s)" → extra attributes; "size mismatch" → re-measure shapes

---

## 3. Compute Baseline MSE

```python
data = torch.load('/app/dataset.pt', map_location='cpu', weights_only=True)
# Inspect: print(type(data)); if dict: print(data.keys())

model.eval()
with torch.no_grad():
    baseline_mse = torch.nn.MSELoss()(model(inputs), targets).item()
```

- [ ] `model.eval()` called BEFORE inference; `torch.no_grad()` used

---

## 4. Freeze and Fine-Tune Only `output_layer`

```python
for p in model.parameters():
    p.requires_grad = False
for n, p in model.named_parameters():
    if 'output_layer' in n:
        p.requires_grad = True

optimizer = torch.optim.Adam(
    [p for n, p in model.named_parameters() if 'output_layer' in n], lr=0.01
)
criterion = torch.nn.MSELoss()

model.train()
for epoch in range(1000):
    optimizer.zero_grad()
    loss = criterion(model(inputs), targets)
    loss.backward()
    optimizer.step()
    if loss.item() < baseline_mse * 0.95:
        break
```

- [ ] Only `output_layer.*` shows `requires_grad=True`; optimizer only sees those params
- [ ] Loss decreases; early-stops at 5% below baseline or max epochs

```python
model.eval()
with torch.no_grad():
    new_mse = torch.nn.MSELoss()(model(inputs), targets).item()
assert new_mse < baseline_mse, f"FAILED: {new_mse} >= {baseline_mse}"
```

---

## 5. Save TorchScript and Verify

```python
torch.jit.script(model).save('/app/model.pt')

loaded = torch.jit.load('/app/model.pt')
# Diff state dicts — only output_layer.* may differ:
original_sd = torch.load('/app/weights.pt', map_location='cpu', weights_only=True)
new_sd = loaded.state_dict()
for k in original_sd:
    if not torch.allclose(original_sd[k], new_sd[k], atol=1e-6):
        assert 'output_layer' in k, f"UNEXPECTED CHANGE: {k}"
```

- [ ] `/app/model.pt` exists, loads, and runs without errors
- [ ] Only `output_layer.*` keys changed; `/app/weights.pt` never modified
