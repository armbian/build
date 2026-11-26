# Investigación: Hub FE1.1S a 480 Mbps (High-Speed) en Cubie A7A (mainline)

## Objetivo
Hacer que el hub USB 2.0 FE1.1S (`1a40:0101`) conectado al controlador DWC3 (`6a00000.usb`, PHY U2P0 en `0x06b00000`) negocie **480 Mbps (High-Speed)** en lugar de **12 Mbps (Full-Speed)**, para habilitar completamente el bus USB y el chip Wi-Fi AIC8800 (`1-1.4`) soldado en placa.

## Estado observado
- `Bus 002` (USB 3.0 SuperSpeed, `6a00000.usb`): funciona a `5000M`.
- `Bus 001` (USB 2.0, `6a00000.usb`, `U2P0`):
  - El hub `1-1` (`1a40:0101`) enumera a `12M` (`PORTSC1 0x06a00430 = 0x00000603`, Speed=1 FS).
  - Los dispositivos `1-1.1`, `1-1.2`, `1-1.3` enumeran a `12M`.
  - El AIC8800 (`1-1.4`) falla con `device descriptor read/64, error -110` / `error -62`.

## Descartado previamente
1. `res_dcap` + `SYSCFG160=00c81532`, `SYSCFG164=00c80000`, `SYSCFG168=c8c80000`: siguió en `12M`.
2. `pll-periph0-480M` forzado a `480 MHz` durante la enumeración: siguió en `12M`.
3. Relojes críticos `msi-lite0`: ya presentes en la base (`a3e01d0395fd`) y activos (`26M/200M/600M`).
4. Cristal `hosc`: `sun60i-a733.dtsi` declara `osc26M` a `26000000`; `pll_ref` normaliza a `24 MHz`.

## Hallazgos de documentación y registros
- **A733 User Manual V0.92 (sección 18.4)**:
  - `0x06B00000` son los Application Registers de `USB3P1_DRD`: `U2P0_ISCR` (`0x00`), `U2P0_PHYCTL` (`0x10`), `U2P0_PHYTUNE` (`0x18`), `U2P0_PHYSTS` (`0x24`).
  - `U2P0_ISCR` bit 25 es `DP` line status (por eso `0x02000000` indica estado J Full-Speed).
  - `sun4i_usb_phy_passby(phy, 1)` escribía `0x701` en `U2P0_ISCR` (`0x06b00000`), lo cual activa bits de interrupción/wakeup de `U2P0_ISCR` que no corresponden a DWC3.
  - `SUBSYS_USB3P1_BGR` (`0x06c00008 = 0x00030010`) selecciona UTMI CLK del PHY USB2 (`bit 21 = 0`) y libera `USB3P1_USB2P0_PHY_RSTN` (`bit 4 = 1`).
- **Esquemático Radxa Cubie A7A V1.10**:
  - `U6` (`FE1_1S`) tiene `DPU`/`DMU` conectados a `USB2-DP`/`USB2-DM`.
  - `XRSTJ` tiene un RC a `VCC_3V3_USB20HUB` (`C155 100nF`).
  - `USB_HOST_EN` (`PM5`) controla el switch VBUS `U5` (`VCC5V0_USB20`).

## Experimentos realizados en esta sesión
1. **Kernel `#26` (`PHYSOFTRST` en `dwc3_core_soft_reset()` para `allwinner,sun60i-a733-dwc3` en modo host)**:
   - Resultado: `1-1` sigue en `12M` (`PORTSC1 = 0x00000603`).
   - Observación: `U2P0_ISCR` seguía con `0x02000711` por `sun4i_usb_phy_passby(phy, 1)`.
2. **Kernel `#27` (`PHYSOFTRST` + quitar `sun4i_usb_phy_passby(phy, 1)` y escribir `0` en `U2P0_ISCR`)**:
   - Resultado: `1-1` sigue en `12M`.

## Comparación directa con BSP vivo (`5.15.147-21-a733`, `192.168.100.99`)
En el BSP, el hub `1-1` (`1a40:0101`) enumera a `480M` (`PORTSC1 0x06a00430 = 0x00000e03`) y el AIC8800 (`1-1.4`) enumera a `480M` con `wlan0` funcional.

Diferencias encontradas entre BSP (480M) y Mainline `#27` (12M):
1. **CCU USB2 (`0x02002000`)**:
   - BSP: `0x1360` (`usb2-u3-utmi`) = `0x00000000` (apagado), `0x1364` (`usb2-u2-pipe`) = `0x00000000` (apagado).
   - Mainline: ambos están habilitados (`0x81000000`, `300M` y `600M`).
2. **Regulador `PM5` (`usb1-vbus` / `reg_usb_host_en`)**:
   - BSP: **no** tiene `regulator-always-on` ni `regulator-boot-on`.
   - Mainline: tiene `regulator-always-on`.
3. **SYSCFG (`0x03000000`)**:
   - BSP: `0x160=00c81532`, `0x164=00c80000`, `0x168=c8c80000`, `0x16c=00000080`.
   - Mainline `#26`: `0x160=00c81502`, `0x164=00c8c8c8`, `0x168=c8c8c800`.
4. **DWC3 Global (`0x06a0c000`)**:
   - BSP: `GCTL=30c11004` (`DSBLCLKGTNG=0`), `GUSB3PIPECTL0=01001102`.
   - Mainline: `GCTL=30c11005` (`DSBLCLKGTNG=1`), `GUSB3PIPECTL0=01021102`.
5. **DTS BSP (`usbc2@12`)**:
   - Tiene `aw,inv-sync-hdr-quirk;` en el glue `allwinner,sunxi-plat-dwc3`.

## Causa raíz y solución verificada (Kernel `#32`)
Se combinaron tres correcciones basadas en el **A733 User Manual V0.92** y la comparación con el **BSP vivo**:
1. **`SERDES_LO + 0x08` (`SUBSYS_USB3P1_BGR`) = `0x00130010` en `drivers/usb/dwc3/dwc3-of-simple.c`**:
   - En `0x00030010`, el bit 20 (`USB3P1_ONLY_PIPE_CLK_SEL`) estaba en `0` (esperando reloj PIPE3 del Combo PHY USB3, que en arranque en frío está apagado).
   - Al poner el bit 20 en `1` (`0x00130010`, *USB2.0 independent working scene*), el DWC3 toma el reloj PIPE desde el CCU (`CLK_USB2_U2_PIPE`) manteniendo el bit 21 en `0` (UTMI desde U2P0). Esto resuelve el `-ETIMEDOUT` (`DCTL.CSFTRST` / `xhci can't setup: -110`) tras ciclo de energía.
2. **Pulso `DWC3_GUSB2PHYCFG_PHYSOFTRST` tras `CSFTRST` en `drivers/usb/dwc3/core.c`**:
   - En `dwc3_core_soft_reset()`, tras completar `DCTL.CSFTRST` en `done:`, si `dr_mode == USB_DR_MODE_HOST` y el padre es `allwinner,sun60i-a733-dwc3`, se pulsa `DWC3_GUSB2PHYCFG_PHYSOFTRST` (50 ms alto, 50 ms bajo) para alinear en fase el reloj UTMI de 60 MHz.
3. **Eliminar `sun4i_usb_phy_passby(phy, 1)` en `U2P0` (`drivers/phy/allwinner/phy-sun4i-usb.c`)**:
   - `passby(1)` escribía `0x701` en `U2P0_ISCR` (`0x06b00000`), registro exclusivo del wrapper DWC3/U2P0 (distinto a EHCI/OHCI PMU). Se escribe `0` limpio en `U2P0_ISCR`.

### Resultado en hardware real (`#32`, `7.3.0-rc1-dev-sun60iw2-dev`)
- `Bus 001`: Hub `1a40:0101` (FE1.1S) enumera a **`480M`**.
- `1-1.1` (`0781:5567` SanDisk) y `1-1.2` (`abcd:1234` UDisk) enumeran a **`480M`**.
- `1-1.4` (`a69c:8d81` AIC8800D80): `aic_btusb` y `aic8800_fdrv` cargan a **`480M`**.
- Interfaz `wlan0` (`18:ce:df:6d:a6:77`) presente y operativa.

## USB 3.x en el puerto azul (`combophy0`) — Kernel `#35`

### Causa del fallback a `480M`
El DTS solo enlazaba `usb2-phy` (`usbphy 2`) en `dwc3` y dejaba `combophy0` sin nodo.
Sin PHY SuperSpeed, xHCI registraba `Bus 002` a `10000M` pero el lector
`8564:4000` (Transcend UHS-II) caía en `Bus 003` (`ehci-platform`) a `480M`.
Además, `SERDES_USB3_BGR` bit 20 (`USB3P1_ONLY_PIPE_CLK_SEL`) seguía en `1`
desde el arranque en frío, por lo que el controlador tomaba PIPE del CCU
(`CLK_USB2_U2_PIPE`) en vez del combo PHY.

### Solución aplicada
1. `0005-phy-sun60i-a733-combophy-add-usb3-support.patch`: modo USB3 para
   `phy-sun60i-a733-combophy.c` con las tablas de registros y la secuencia de
   reset del BSP. Compatible `allwinner,sun60i-a733-usb3-phy`, limpia el bit
   `USB3P1_ONLY_PIPE_CLK_SEL` mediante `allwinner,serdes`, y mapea la región
   `pipe` (`0x06c06000`) con `devm_ioremap()` para no colisionar con
   `combophy1` (PCIe).
2. `0006-arm64-dts-allwinner-a733-enable-usb3-combophy0.patch`: nodo
   `combophy0` (`0x06c01000` / `0x06c80000` / `0x06c06000`), `maximum-speed =
   "super-speed-plus"`, quirks U1/U2/U3, `status = "okay"` en la placa y
   `CLK_SERDES_USB3_PIPE` eliminado de `assigned-clocks`.

### Resultado en hardware real (`#35`, `7.3.0-rc1-dev-sun60iw2-dev`)
- `Bus 002` (`xhci-hcd/1p`, `10000M`): lector `8564:4000` a **`5000M`**.
- `Bus 001` (`xhci-hcd/1p`, `480M`): hub `1a40:0101` y AIC8800 `a69c:8d81`
  a **`480M`**, sin regresión.
- `dmesg`: `Host supports USB 3.1 Enhanced SuperSpeed`,
  `usb 2-1: new SuperSpeed USB device number 2`.

### Pendiente
- Parche obsoleto `0004-usb-dwc3-use-gctl-reset-on-a733.patch` sin seguimiento
  en git: Armbian lo aplicaría en una compilación nueva y su `return 0;`
  anticipado deja sin efecto el quirk `snps,phy-soft-reset-after-csftrst`
  validado en `#35`. Eliminar antes de regenerar la imagen completa.
