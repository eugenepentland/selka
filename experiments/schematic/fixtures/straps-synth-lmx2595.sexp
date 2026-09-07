(import lmx2595rhar cap-0603)

;; LMX2595 PLL synthesizer for the Straps base board — the U7 block of the KiCad
;; project "Black_Canyon_Base_Board" (/mnt/nas/straps/boards/straps_base_board)
;; with four deliberate changes away from what is on the fabbed board. Everything
;; NOT listed here is the board's own circuit, part for part and value for value,
;; and each such instance carries its board ref-des in a trailing comment.
;;
;; CHANGED vs the fabbed straps board:
;;   1. REFERENCE IS NOW DIFFERENTIAL. The board drives OSCINP single-ended (50R
;;      shunt to ground + one 0.1 uF block) and floats OSCINM. This module
;;      terminates a differential pair with 100R across it and AC-couples BOTH
;;      legs, matching bcuda-synth-lmx2595. ⚠ This changes what the board must
;;      feed it — see the REFERENCE SOURCE note at the bottom.
;;   2. LO IS NOW TAKEN FROM RFOUTA, NOT RFOUTB. The whole output network moved
;;      to port A. PORT-B DISPOSITION (user decision 2026-08-31): port B is
;;      UNUSED — RFOUTBP/RFOUTBM are UNPOPULATED (no pull-ups, no bias tee;
;;      both nets are deliberate dead-end stubs at the QFN pads) and the
;;      firmware register image keeps the buffer powered down (OUTB_PD = 1).
;;      An earlier revision of this header claimed a port-B bias tee that was
;;      never re-created after the port-A move; three false sign-offs to that
;;      effect were retracted 2026-08-31 (barracuda.checks.sexp) and the three
;;      pull-up requirements are now consciously waived for the permanently
;;      disabled port.
;;   3. THE FOUR 10 uF BIAS CAPS ARE 0603, NOT 0402 — the one place where the
;;      barracuda module used a larger package than the straps board. Every other
;;      cap here is the same size as or larger than its barracuda counterpart
;;      (barracuda's 1 uF and 100 nF parts are 0201), so nothing else moves.
;;   4. THE NFM31 RAIL FILTER IS DROPPED — see the Supply decoupling block. The
;;      six 1 uF VCC caps are UNCHANGED and are the WHOLE supply bypass: that bank
;;      is TI's reference design, not an oversight to be padded with 100 nF parts
;;      or a bulk reservoir.
(defmodule straps-synth-lmx2595 ()
  "LMX2595 PLL synth (Straps): differential REF_P/REF_N in, RFOUTA choke-fed LO_OUT, RFOUTB unused/unpopulated (OUTB_PD=1), SPI, single 3.3 V."
  (implements lmx2595rhar (policy recommended) (role synthesizer))
  (design-block "LMX2595 PLL Synth (Straps)"

    ;; ── U7 ──────────────────────────────────────────────────────────────────
    (instance "U1" lmx2595rhar
      (pin 1 "LMX_CE")
      (pin 2 4 6 13 14 25 31 34 39 40 41 "GND")
      (pin 3 "LMX_VBIASVCO")
      ;; ICC = 340 mA typ at VCC 3.3 V (SNAS736C §6.5, p9). The datasheet's stated
      ;; condition is exactly this module's configuration — OUTA_PD = 0 with
      ;; OUTB_PD = 1 (one buffer live, the other down), OUTA_PWR = 31 (the
      ;; mid-scale register default), fPD = 100 MHz, +3 dBm into a 50 R pull-up —
      ;; measured at fOUT = 14 GHz. No larger ICC is expected for Barracuda's
      ;; 10.95 GHz configuration (same signal path: doubler off, no channel
      ;; divider, inside the 7.5-15 GHz VCO fundamental range), so 340 mA is the
      ;; board's typical and maximum design load. The annotation rides the first
      ;; pad and rolls up all six VCC pins: 3.3 V x 340 mA = 1.12 W, the largest
      ;; single dissipation on the board.
      ;; Give each VCC pad its own bypass stub. All six stub names collapse to
      ;; the V_3V3 rail electrically and render with the shared rail label, but
      ;; they remain separate local cap branches in the schematic and PCB plan.
      (pin 7  "V_3V3.U1.7" (i-typ 0.34) (i-max 0.34))  ;; VCCDIG; carries whole-device ICC annotation
      (pin 11 "V_3V3.U1.11")                          ;; VCCCP
      (pin 15 "V_3V3.U1.15")                          ;; VCCMASH
      (pin 21 "V_3V3.U1.21")                          ;; VCCBUF
      (pin 26 "V_3V3.U1.26")                          ;; VCCVCO2
      (pin 37 "V_3V3.U1.37")                          ;; VCCVCO
      (pin 8 "LMX_OSCIN_P")
      (pin 9 "LMX_OSCIN_N")               ;; CHANGED — driven, was floating
      (pin 10 "LMX_VREGIN")               ;; regulator OUTPUT — cap only, no rail tie
      (pin 12 "LMX_CPOUT")
      (pin 16 "SPI_SCK")
      (pin 17 "SPI_SDI")
      (pin 18 "LMX_RFOUTBM")              ;; unused buffer — UNPOPULATED, OUTB_PD=1 (dead-end stub, waived)
      (pin 19 "LMX_RFOUTBP")              ;; unused buffer — UNPOPULATED, OUTB_PD=1 (dead-end stub, waived)
      (pin 20 "SPI_SDO")                  ;; MUXOUT (readback / lock detect)
      (pin 22 "LMX_RFOUTAM")              ;; CHANGED — now the active LO buffer
      (pin 23 "LMX_RFOUTAP")              ;; CHANGED — now the active LO buffer
      (pin 24 "SPI_CSN")
      (pin 27 "LMX_VBIASVCO2")
      (pin 29 "LMX_VREFVCO2")
      (pin 33 "LMX_VBIASVARAC")
      (pin 35 "LMX_VTUNE")
      (pin 36 "LMX_VREFVCO")
      (pin 38 "LMX_VREGVCO")
      ;; Deliberate no-connects, as on the board.
      (nc-ok 5  "SYNC — phase-sync input unused; the board runs one free-standing synth, no SYSREF/JESD204B")
      (nc-ok 28 "SYSREFREQ — JESD204B SYSREF request unused")
      (nc-ok 30 "RAMPCLK — internal ramp/FSK engine unused (CW LO only)")
      (nc-ok 32 "RAMPDIR — internal ramp/FSK engine unused (CW LO only)") (id e7e79244))

    ;; ── Supply decoupling ───────────────────────────────────────────────────
    ;; The straps board feeds this rail from the board's shared +3.3 V through an
    ;; NFM31KC223R1H3L 3-terminal feedthrough filter (C76) and bypasses it with
    ;; nothing but six 1 uF parts. Both are dropped here: the destination rail is
    ;; a DEDICATED low-noise LDO (barracuda's V_3V3_LMX, an LT3045 feeding only
    ;; this chip), so the filter has no other loads to isolate against — and it
    ;; carries a U ref-des, which on a shared numbering pass shifts every U on the
    ;; host board and orphans its verification sign-offs.
    ;;
    ;; The six 1 uF parts STAY exactly as the board has them: that is TI's own
    ;; reference design — the LMX2594/95 EVM bypasses each VCC pin with a single
    ;; 1 uF (C26 VCCDIG, C29 VCCCP, C18 VCCMASH, C23 VCCVCO2, C27 VCCBUF, 1 uF on
    ;; VCCVCO) and adds no 100 nF HF parts at all. Do not "improve" this with a
    ;; parallel 100 nF bank on SRF-of-an-0402 reasoning; the EVM is the authority
    ;; and the 0.1 uF that does appear on the EVM (C30) is on VccRF feeding the
    ;; bias tee, not on the supply pins.
    ;;
    ;; No separate bulk reservoir either: on the intended host the LT3045's own
    ;; output capacitor is the reservoir. Five VCC pins retain the EVM's 1 uF
    ;; bypass; C_VCCVCO2 is intentionally increased to 10 uF.
    ;; These explicit per-pin stubs are the same topology emitted by the
    ;; (decouple … per-pin …) shorthand, while retaining the established
    ;; component names and PCB identities.
    (instance "C_VCCDIG"  (cap-0402 "1uF" x5r "10%" "25V") (pin 1 "V_3V3.U1.7")  (pin 2 "GND") (decouples "U1" 7)  (id de80d423))  ;; C54
    (instance "C_VCCCP"   (cap-0402 "1uF" x5r "10%" "25V") (pin 1 "V_3V3.U1.11") (pin 2 "GND") (decouples "U1" 11) (id ed978348))  ;; C55
    (instance "C_VCCMASH" (cap-0402 "1uF" x5r "10%" "25V") (pin 1 "V_3V3.U1.15") (pin 2 "GND") (decouples "U1" 15) (id b49cc3cd))  ;; C56
    (instance "C_VCCBUF"  (cap-0402 "1uF" x5r "10%" "25V") (pin 1 "V_3V3.U1.21") (pin 2 "GND") (decouples "U1" 21) (id bfcd2527))  ;; C58
    (instance "C_VCCVCO2" (cap-0603 "10uF" x6s "20%" "10V") (pin 1 "V_3V3.U1.26") (pin 2 "GND") (decouples "U1" 26) (id da983857)) ;; C61
    (instance "C_VCCVCO"  (cap-0402 "1uF" x5r "10%" "25V") (pin 1 "V_3V3.U1.37") (pin 2 "GND") (decouples "U1" 37) (id f42eb769))  ;; C62

    ;; ── Internal regulator / bias bypass ────────────────────────────────────
    ;; Values are the board's; the four 10 uF parts are UPSIZED 0402 → 0603 to
    ;; match bcuda-synth-lmx2595 (real 10 uF capacitance under DC bias in an 0402
    ;; is marginal — an 0603 part of the same nominal value keeps far more of it).
    ;; The 1 uF parts stay 0402: barracuda's are 0201, i.e. already smaller.
    (instance "C_VREGIN"     (cap-0402 "1uF" x5r "10%" "25V")  (pin 1 "LMX_VREGIN")     (pin 2 "GND") (id a9cc89aa))  ;; C63
    (instance "C_VREGVCO"    (cap-0402 "1uF" x5r "10%" "25V")  (pin 1 "LMX_VREGVCO")    (pin 2 "GND") (id a82b4170))  ;; C64
    (instance "C_VBIASVCO"   (cap-0603 "10uF" x6s "20%" "10V") (pin 1 "LMX_VBIASVCO")   (pin 2 "GND") (id e068fe4c))  ;; C65 — upsized
    (instance "C_VBIASVCO2"  (cap-0402 "1uF" x5r "10%" "25V")  (pin 1 "LMX_VBIASVCO2")  (pin 2 "GND") (id dd2ec5b7))  ;; C52
    (instance "C_VBIASVARAC" (cap-0603 "10uF" x6s "20%" "10V") (pin 1 "LMX_VBIASVARAC") (pin 2 "GND") (id ea33bd3c))  ;; C66 — upsized
    (instance "C_VREFVCO"    (cap-0603 "10uF" x6s "20%" "10V") (pin 1 "LMX_VREFVCO")    (pin 2 "GND") (id b5bb9043))  ;; C48 — upsized
    (instance "C_VREFVCO2"   (cap-0603 "10uF" x6s "20%" "10V") (pin 1 "LMX_VREFVCO2")   (pin 2 "GND") (id f54a5faf))  ;; C51 — upsized

    ;; ── Chip enable: 10k pull-up, always on ────────────────────────────────
    ;; LMX2595 input leakage is specified as high as +/-25 uA. The inherited
    ;; 100 k value could therefore lose 2.5 V and did not guarantee VIH; 10 k
    ;; limits that error to 0.25 V while retaining an always-on default.
    (instance "R_CE" (res-0402 "10k" "1%" "0.063W" "50V" "100ppm/C") (pin 1 "V_3V3") (pin 2 "LMX_CE") (id c75b17f4))  ;; R37

    ;; ── Reference input — DIFFERENTIAL (changed from the board) ─────────────
    ;; 100R across the pair at the receiver, then AC-couple each leg into the
    ;; self-biased OSCINP/OSCINM. Replaces the board's 50R-to-ground shunt (R38)
    ;; and its single 0.1 uF block (C53) into OSCINP with OSCINM floating.
    ;; 0.1 uF is the board's own coupling value and the datasheet recommendation.
    (instance "R_OSC_TERM" (res-0402 "100R" "1%" "0.063W" "50V")  (pin 1 "REF_P") (pin 2 "REF_N") (id c7abd7da))
    (instance "C_OSCINP"   (cap-0402 "0.1uF" x7r "10%" "25V") (pin 1 "REF_P") (pin 2 "LMX_OSCIN_P") (id ee15dbc0))
    (instance "C_OSCINM"   (cap-0402 "0.1uF" x7r "10%" "25V") (pin 1 "REF_N") (pin 2 "LMX_OSCIN_N") (id e3b98eb8))

    ;; ── PLL loop filter (TI LMX2595 EVM values) ─────────────────────────────
    ;; C1 shunt at CPOUT, the series C2+R2 type-II zero (cap on the CPOUT side,
    ;; resistor at the ground end), R3 into VTUNE, C3 shunt at VTUNE.
    (instance "C_LF1" (cap-0402 "390pF" np0 "5%" "50V")   (pin 1 "LMX_CPOUT")   (pin 2 "GND") (id f1ff5923))           ;; C69
    (instance "C_LF2" (cap-0402 "0.068uF" x7r "10%" "25V") (pin 1 "LMX_CPOUT")   (pin 2 "LMX_LF_ZERO") (id f737b14f))   ;; C71
    (instance "R_LF2" (res-0402 "68R" "1%" "0.063W" "50V")     (pin 1 "LMX_LF_ZERO") (pin 2 "GND") (id c5ee052a))           ;; R44
    (instance "R_LF3" (res-0402 "18R" "1%" "0.063W" "50V")     (pin 1 "LMX_VTUNE")   (pin 2 "LMX_CPOUT") (id bf31a52b))     ;; R42
    (instance "C_LF3" (cap-0402 "1800pF" np0 "5%" "50V")  (pin 1 "LMX_VTUNE")   (pin 2 "GND") (id ee8a6f22))           ;; C67

    ;; ── LO output: RFOUTA, choke-fed from the separate RF rail ──────────────
    ;; The board's port-B network, moved intact to port A. L7 18 nH feeds LO_BIAS_A
    ;; from V_3V3 and C68 bypasses it, so LO_BIAS_A is an RF ground at DC 3.3 V —
    ;; each open-collector leg therefore sees its 50R load through its pull-up, and
    ;; the L/C pair keeps the LO out of the rail and the rail's noise off the LO.
    ;; The used leg (AP) goes out through the 0.01 uF block; the complementary leg
    ;; (AM) is likewise AC-coupled before its 50R ground termination, so neither
    ;; output pad has a DC path to ground and the buffer keeps its balanced RF load.
    (instance "L_LO_BIAS_A" (ind-0402 "18nH" "5%" "0.4A" "0.36ohm")   (pin 2 "V_3V3")       (pin 1 "LO_BIAS_A") (id bff51a4b))     ;; L7
    (instance "C_LO_BIAS_A" (cap-0402 "0.01uF" x7r "10%" "16V") (pin 1 "LO_BIAS_A")   (pin 2 "GND") (id fc471d8d))           ;; C68
    (instance "R_RFOUTAP"   (res-0402 "50R" "0.1%" "0.05W" "50V" rf-termination)    (pin 1 "LMX_RFOUTAP") (pin 2 "LO_BIAS_A") (id ca0d8b70))     ;; was R41 on B
    (instance "R_RFOUTAM"   (res-0402 "50R" "0.1%" "0.05W" "50V" rf-termination)    (pin 1 "LO_BIAS_A")   (pin 2 "LMX_RFOUTAM") (id e572a8e2))   ;; was R40 on B
    (instance "C_RFOUTAM_T" (cap-0402 "0.01uF" x7r "10%" "16V") (pin 1 "LMX_RFOUTAM") (pin 2 "RFOUTAM_TERM") (id a0c4ec66))                ;; NEW DC block
    (instance "R_RFOUTAM_T" (res-0402 "50R" "0.1%" "0.05W" "50V" rf-termination)    (pin 1 "RFOUTAM_TERM") (pin 2 "GND") (id f8fab82b))          ;; was R39 on B
    (instance "C_LO_AC"     (cap-0402 "0.01uF" x7r "10%" "16V") (pin 1 "LO_OUT")      (pin 2 "LMX_RFOUTAP") (id b498eebd))   ;; was C70 on B

    ;; Unused port B, on its OWN bias tee. A second 18 nH choke + 0.01 uF bypass
    ;; give port B an independent RF-grounded bias node, so the two buffers share
    ;; only the V_3V3 rail and no longer meet at a common node — enabling B can
    ;; no longer push anything onto A's bias. A node needs BOTH parts to be an RF
    ;; ground, hence the second cap alongside the second choke. No ground-leg
    ;; resistor on B: neither leg drives anything. To press B into service later,
    ;; add a 0.01 uF block off BP and a 50R-to-ground on BM, mirroring port A.
     ;; NEW
           ;; NEW
     ;; NEW
     ;; NEW

    ;; ── Module-owned envelopes ──────────────────────────────────────────────
    ;; These nodes belong to this module, not to any board, so the DC-rating
    ;; envelope is declared ONCE here instead of being restated once per
    ;; instantiation in every board file that drops this block in. Migrated out
    ;; of src/boards/barracuda/barracuda.sexp, which used to carry the same
    ;; arithmetic under the "lmx2595/..." flattened names.
    ;;
    ;; ── LMX2595 internal regulator and bias pins ──
    ;; TI's Table 42 "Bias Levels of Pins" (SNAS736C p67) gives one TYPICAL
    ;; level per pin and no min/max, so a typical cannot be a bound. Each of
    ;; these nets carries only its bypass capacitor and the pin itself, so the
    ;; honest bound is the device's own supply: nothing on the net can exceed
    ;; the module's own 3.3 V V_3V3 port, which feeds the regulator producing it.
    (net-envelope "LMX_VREGIN" (rated 0.0 3.3)
      "Input reference-path regulator output, 1 uF bypass only (SNAS736C Pin Functions p7). No level is published for it — it is absent from Table 42 — so it is bounded by its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VREGVCO" (rated 0.0 3.3)
      "VCO regulator output behind its bypass capacitor; SNAS736C Table 42 p67 gives 2.1 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VBIASVCO" (rated 0.0 3.3)
      "VCO bias node behind its 10 uF bypass; SNAS736C Table 42 p67 gives 1.3 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VBIASVCO2" (rated 0.0 3.3)
      "Second VCO bias node behind its bypass; SNAS736C Table 42 p67 gives 0.7 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VBIASVARAC" (rated 0.0 3.3)
      "VCO varactor bias behind its 10 uF bypass; SNAS736C Table 42 p67 gives 1.7 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VREFVCO" (rated 0.0 3.3)
      "VCO supply reference behind its 10 uF bypass; SNAS736C Table 42 p67 gives 2.9 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_VREFVCO2" (rated 0.0 3.3)
      "Second VCO supply reference behind its 10 uF bypass; SNAS736C Table 42 p67 gives 2.9 V TYPICAL with no min/max, so the bound is its own supply, this module's declared 3.3 V V_3V3 port")
    (net-envelope "LMX_CE" (rated 0.0 3.3)
      "Chip-enable, active HIGH (SNAS736C Pin Functions p7), held up by this module's R_CE 10k from its V_3V3 port; the CMOS input's +/-25 uA leakage (6.5 Digital Interface p12) can drop at most 0.25 V across that pull-up, so the net spans 0 V to the declared 3.3 V supply")

    (port "REF_P"    in  signal)
    (port "REF_N"    in  signal)
    (port "LO_OUT"   out rf)
    (port "V_3V3"    in  power (nominal 3.3))
    ;; The LMX2595's four-wire MICROWIRE port as one bundle rather than four
    ;; loose ports (ERC interface_naming). TI spells the lanes SDI / SDO / CSB,
    ;; so the group renames MOSI/MISO/CS to the names already in use; every
    ;; port name is unchanged and no board bridge changes.
    (port-group "SPI" spi (rename MOSI "SPI_SDI") (rename MISO "SPI_SDO")
                          (rename CS "SPI_CSN"))
    (port "GND"      bidi)

    ;; Two members each ⇒ paired directly. Geometry is the destination board's.
    (net-class "ref-in"    (diff-pair) (nets "REF_P" "REF_N"))
    (net-class "ref-oscin" (diff-pair) (nets "LMX_OSCIN_P" "LMX_OSCIN_N"))

    (net-class "rf"
      (nets "LMX_RFOUTAP" "LMX_RFOUTAM" "RFOUTAM_TERM" "LMX_RFOUTBP" "LMX_RFOUTBM" "LO_OUT"))

    ;; Keep the compact loop-filter chain on the component face, then carry
    ;; VTUNE between its distant resistor and IC/cap branch on the quiet back
    ;; face. This is the same two-via topology as the blessed hand layout, but
    ;; remains placement-relative: the router chooses both transitions.
    (pcb-plan
      (route
        (wave "loop-filter-cpout"
          (nets "LMX_CPOUT")
          (preferred-layers "F.Cu")
          (allowed-layers "F.Cu")
          (reason "join the adjacent charge-pump filter pads before bulk copper"))
        (wave "loop-filter-vtune"
          (nets "LMX_VTUNE")
          (preferred-layers "B.Cu")
          (allowed-layers "F.Cu" "B.Cu")
          (max-vias 2)
          (reason "use two local transitions and carry the long tuning leg on B.Cu"))
        (wave "rest" (rest))))

    (rough
      (anchor "U1")
      (group "loopfilter" C_LF1 C_LF2 R_LF2 R_LF3 C_LF3)
      (group "ref"        R_OSC_TERM C_OSCINP C_OSCINM)
      ;; (no "lo_bias_b" group: port B is unpopulated by disposition — the old
      ;; group named parts that do not exist and was silently inert.)
      (group "lo_out_a"   L_LO_BIAS_A C_LO_BIAS_A R_RFOUTAP R_RFOUTAM C_RFOUTAM_T R_RFOUTAM_T C_LO_AC)
      (group "supply"     C_VCCDIG C_VCCCP C_VCCMASH C_VCCBUF C_VCCVCO2 C_VCCVCO)
      (group "bias"       C_VREGIN C_VREGVCO C_VBIASVCO C_VBIASVCO2 C_VBIASVARAC C_VREFVCO C_VREFVCO2))

    (note "U1" "Derived from the Straps base board (KiCad 'Black_Canyon_Base_Board', U7 block). Supply is a single 3.3 V port; the board's NFM31KC223R1H3L feedthrough filter (C76) is dropped because the destination rail is a dedicated LT3045 with no other loads to isolate against. VCC bypass is TI's reference-design arrangement, unchanged from the board: ONE 1 uF per supply pin and nothing else — no parallel 100 nF bank and no bulk reservoir (the EVM has neither; on the intended host the LT3045's output cap is the reservoir). VREGIN (pin 10) is a BYPASS pin, not a supply — the datasheet calls it the 'input reference path regulator output' and asks only for a 1 uF cap to ground close to the pin (C63) — so it is correctly left off the 3.3 V rail here. bcuda-synth-lmx2595 (retired here 2026-08-07) and cyclops-xband-lo (fixed 2026-08-07) both tied pin 10 to their VCC rail instead.")

    (note "U1" "REFERENCE SOURCE — ACTION REQUIRED ON THE BOARD. This module now expects a DIFFERENTIAL reference on REF_P/REF_N (100R across the pair, 0.1 uF into each leg). The fabbed straps board cannot feed that: its reference is the SI53361 clock buffer's single-ended LVCMOS Q0 through a 33R series resistor (R52). Driving REF_P from that source and leaving REF_N open would be worse than the single-ended circuit it replaced, because the 100R now sits across a pair with only one leg driven. To use this module the board needs a genuine differential source — an LVDS/LVPECL output (the barracuda board takes its 100 MHz pair off an LMK05318B) or a single-ended-to-differential conversion ahead of it. R52 and R38 both go away in that rework.")

    (note "U1" "LO OUTPUT MOVED TO RFOUTA. The straps board takes its LO off RFOUTB and leaves RFOUTA open and unbiased; here the whole network — 18 nH choke L7, 0.01 uF bypass C68, the two 50R pull-ups, the AC-coupled 50R idle-leg termination and the 0.01 uF output block C70 — sits on port A instead. Both buffers are fed from the same VCO/divider chain, so this costs nothing in performance.")

    (note "U1" "PORT-B DISPOSITION — UNUSED, UNPOPULATED, DISABLED (user decision 2026-08-31). RFOUTBP (19) and RFOUTBM (18) carry NO external network: no 50R pull-ups, no bias tee, no DC block — both nets are deliberate dead-end stubs ending at the QFN pads (the schematic warnings naming them are expected). The FIRMWARE CONTRACT keeps the buffer powered down: the release register image sets OUTB_PD = 1 and never selects OUTB_MUX = channel divider/SysRef (LMX2595.pdf Table 9 — so the channel divider is not spuriously powered either); port B must not be enabled on this hardware, because LMX2595.pdf Pin Functions p.7 requires a ~50R pull-up to VCC on each leg and section 10.1 p.68 requires the complementary leg to carry the same load before the buffer may drive. With OUTB_PD = 1 the open-collector output stage is off and sources no current, so the unpowered, unloaded pins are electrically inert; the datasheet's own EC-table note measures the device with the 'unused port terminated' only because both ports are ENABLED in that characterization. Bringing port B up later is a REWORK, not a register write: fit the port-B bias tee (18 nH choke + 0.01 uF off V_3V3), 50R pull-ups on both legs, a DC block on BP and a 50R idle-leg termination on BM — then re-open requirements b520171a/6bdc7a58/1666d0da, whose 2026-08-31 waivers are conditioned on the port staying disabled.")

    (note "U1" "PORT-A BIAS TEE, per the TI LMX2594/95 EVM (which feeds its 50R pull-ups through an 18 nH choke — L2 — from VccRF): an 18 nH choke from V_3V3 into the 0.01 uF-bypassed bias node LO_BIAS_A. The node needs BOTH parts — the choke alone does not make an RF ground. The EVM and the straps board both give the choke its own rail (VccRF / +3.3V_RF); here it rides the module's single V_3V3 port, which on a board whose 3.3 V is already a dedicated low-noise LDO (barracuda's V_3V3_LMX) is the same node either way. CORRECTED 2026-08-31: an earlier revision of this note described a second (port-B) bias tee that was never instantiated — port B is unpopulated and disabled by disposition; see the PORT-B DISPOSITION note.")

    (note "U1" "Loop filter = TI LMX2595 EVM values (C1 390 pF, C2 0.068 uF + R2 68R series zero, R3 18R, C3 1800 pF) — bit-for-bit the same filter as bcuda-synth-lmx2595, only with the zero branch drawn cap-first (C71 on CPOUT, R44 to ground) rather than resistor-first. Electrically identical series branch; the cap-first order keeps the resistor's noisy node off the high-impedance CPOUT pin.")

    (note "U1" "Board-level parts deliberately left OUT of this module, because they sit on nets shared with the rest of the board: the SPI bus ferrites FB4/FB5/FB6 (1K @ 100 MHz, 0402) between SCLK/MOSI/MISO and the Pi header J5, the 10K bus pull-ups R24/R25 to +3.3 V on MOSI and SCLK, the MUXOUT/MISO indicator LED (R43 1K + D1), and the LO output chain after the DC block (FL1 HFCG-1630+ high-pass -> IC17 YAT-3A+ pad -> IC16 MNA-7A+ gain block). There is no CSN pull-up on this board.")))
