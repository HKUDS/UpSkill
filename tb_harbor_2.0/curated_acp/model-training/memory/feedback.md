---
name: pytorch-model-reconstruction-feedback
description: Winning approach for reconstructing a PyTorch model from a state dict, freezing layers, and fine-tuning only the output layer
metadata:
  type: feedback
---

# Rule
When given a PyTorch state dict and asked to reconstruct a model, always start by printing every key with its shape and dtype. Never guess the architecture. Build the model class with attribute names that exactly match state dict key prefixes. Freeze all parameters except `output_layer` before fine-tuning. Save as TorchScript via `torch.jit.script()`.

**Why:** The state dict keys are the single source of truth for the model architecture. Guessing leads to `load_state_dict` failures from mismatched names or shapes. Freezing non-output layers is required by the task constraints — only `output_layer` weights may change. `torch.jit.script()` is preferred over `torch.jit.trace()` because it handles control flow and is less brittle.

**How to apply:**
1. `torch.load('/app/weights.pt', weights_only=True)` and print all `(key, shape, dtype)` tuples — this is step zero, before any code
2. Classify each key prefix by convention: `.weight`+`.bias` → Linear; `.weight` only 2D → Embedding; `.weight`+`.bias` 1D → LayerNorm; `in_proj_weight` → MultiheadAttention; `weight_ih_l0` → LSTM/GRU
3. Name `__init__` attributes to match key prefixes exactly (e.g., `self.output_layer = nn.Linear(...)` for keys like `output_layer.weight`)
4. Call `model.load_state_dict(sd)` before any training to verify the architecture match
5. Freeze: `for p in model.parameters(): p.requires_grad = False`, then unfreeze only `output_layer`
6. Train with Adam (`lr=0.01`), early-stop when MSE drops 5% below baseline
7. Save: `torch.jit.script(model).save('/app/model.pt')`
8. Verify: reload the TorchScript model and diff state dicts — only `output_layer.*` keys should differ

Related: [[pytorch-state-dict-inspection]] [[torchscript-saving-patterns]]
