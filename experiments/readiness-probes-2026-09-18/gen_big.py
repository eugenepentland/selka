"""Generate the 1.29 MB KiCad-like input used by docs/audits/real-project-readiness-2026-09-18.md."""
import random
random.seed(1)
parts = ['(kicad_pcb (version 20240108) (generator "pcbnew")']
for i in range(4000):
    parts.append(f'  (net {i} "N${i}")')
for i in range(3000):
    parts.append(
        f'  (footprint "Resistor_SMD:R_0402" (layer "F.Cu") (at {i%100}.{i%7} {i//100}.5 90)\n'
        f'    (property "Reference" "R{i}" (at 0 0) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))))\n'
        f'    (pad "1" smd roundrect (at -0.485 0) (size 0.59 0.64) (layers "F.Cu" "F.Paste" "F.Mask") (net {i%4000} "N${i%4000}"))\n'
        f'    (pad "2" smd roundrect (at 0.485 0) (size 0.59 0.64) (layers "F.Cu" "F.Paste" "F.Mask") (net {(i+1)%4000} "N${(i+1)%4000}")))')
parts.append(')')
open('big.kicad_pcb', 'w').write('\n'.join(parts))
