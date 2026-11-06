const {test, expect} = require("@playwright/test")
const AxeBuilder = require("@axe-core/playwright").default

async function createGame(page, mode = "multiplayer") {
  await page.goto("/")
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/)
  await page.locator(mode === "ai" ? "#create-ai-game-button" : "#create-game-button").click()
  await expect(page).toHaveURL(/\/games\/[^/]+$/)
  await expect(page.locator("#breakthrough-board")).toBeVisible()
  return page.url()
}

async function joinGame(browser, url) {
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto(url)
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/)
  return {context, page}
}

async function checkLayout(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  const board = await page.locator("#breakthrough-board").boundingBox()
  expect(board.x).toBeGreaterThanOrEqual(0)
  expect(board.x + board.width).toBeLessThanOrEqual(page.viewportSize().width)
  const squares = await page.locator("#breakthrough-board button").evaluateAll((nodes) => nodes.map((node) => {
    const r = node.getBoundingClientRect()
    return {width: r.width, height: r.height}
  }))
  expect(squares).toHaveLength(64)
  for (const square of squares) {
    expect(square.width).toBeGreaterThan(28)
    expect(Math.abs(square.width - square.height)).toBeLessThan(1)
  }
}

async function capture(page, testInfo, name) {
  const path = testInfo.outputPath(`${name}.png`)
  await page.screenshot({path, fullPage: !name.includes("dialog"), animations: "disabled"})
  await testInfo.attach(name, {path, contentType: "image/png"})
}

test("waiting invitation, same-session limit, clipboard, rules, and cancellation", async ({page, context}, testInfo) => {
  const url = await createGame(page)
  await expect(page.locator("#phase-value")).toHaveText("Invite a friend to play")
  await capture(page, testInfo, "waiting-table")
  await context.grantPermissions(["clipboard-read", "clipboard-write"])
  await page.locator("#copy-link-button").click()
  await expect(page.locator("[data-copy-label]")).toHaveText("Copied")
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(url)
  await expect(page.locator("#copy-link-button .hero-link")).toHaveCount(1)

  const otherTab = await context.newPage()
  await otherTab.goto("/")
  await expect(otherTab.locator("[data-phx-main]")).toHaveClass(/phx-connected/)
  await expect(otherTab.locator("#current-created-game")).toHaveAttribute("data-game-id", url.split("/").pop())
  for (const id of ["#create-ai-game-button", "#create-game-button"]) {
    await otherTab.locator(id).click()
    await expect(otherTab).toHaveURL(/\/$/)
    await expect(otherTab.locator("#new-game-notice")).toContainText("A new game wasn’t created")
    await expect(otherTab.locator("#new-game-notice")).toBeInViewport()
  }
  await capture(otherTab, testInfo, "lobby-current-game")
  const lobbyScan = await new AxeBuilder({page: otherTab}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze()
  expect(lobbyScan.violations).toEqual([])
  await otherTab.locator("#return-to-current-game").click()
  await expect(otherTab).toHaveURL(url)
  await otherTab.close()

  await page.locator("#game-rules-button").click()
  await expect(page.locator("#rules-dialog")).toBeVisible()
  await expect(page.locator("#close-rules-button")).toBeFocused()
  const rulesScan = await new AxeBuilder({page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze()
  expect(rulesScan.violations).toEqual([])
  await capture(page, testInfo, "rules-dialog")
  await page.keyboard.press("Tab")
  await expect(page.locator("#close-rules-button")).toBeFocused()
  await page.keyboard.press("Escape")
  await expect(page.locator("#rules-dialog")).toBeHidden()
  await expect(page.locator("#game-rules-button")).toBeFocused()

  await page.locator("#cancel-game-button").click()
  await expect(page).toHaveURL(/\/$/)
  await expect(page.locator("#home-info-banner")).toContainText("cancelled")
  await page.locator("#create-ai-game-button").click()
  await expect(page).toHaveURL(/\/games\/[^/]+$/)
  expect(page.url()).not.toBe(url)
})

test("two players and a spectator see synchronized moves with spatial keyboard navigation", async ({page, browser}) => {
  const url = await createGame(page)
  const black = await joinGame(browser, url)
  const watcher = await joinGame(browser, url)
  try {
    await expect(page.locator("#phase-value")).toHaveText("Your move")
    await expect(black.page.locator("#player-side-value")).toHaveAttribute("data-side", "black")
    await expect(watcher.page.locator("#player-side-value")).toHaveAttribute("data-side", "spectator")
    await expect(watcher.page.locator("#phase-value")).toHaveText("White to move")
    await expect(black.page.locator("#board-files > span:nth-child(2)")).toHaveText("h")
    await black.page.locator("#square-h2").focus()
    await black.page.keyboard.press("ArrowUp")
    await expect(black.page.locator("#square-h3")).toBeFocused()
    await black.page.keyboard.press("Enter")
    await expect(black.page.locator("#square-h3")).toHaveAttribute("data-selected", "false")

    await page.locator("#square-a7").focus()
    await page.keyboard.press("Enter")
    await expect(page.locator("#square-a7")).toHaveAttribute("data-selected", "true")
    await expect(page.locator("#selection-announcement")).toContainText("a2 selected")
    await page.keyboard.press("ArrowUp")
    await expect(page.locator("#square-a6")).toBeFocused()
    await expect(page.locator("#square-a6")).toHaveAccessibleName(/a3, legal destination/)
    await page.keyboard.press("Enter")
    await expect(page.locator("#square-a6")).toHaveAttribute("data-piece", "W")
    await expect(black.page.locator("#phase-value")).toHaveText("Your move")
    await expect(watcher.page.locator("#phase-value")).toHaveText("Black to move")
    await expect(watcher.page.locator("#move-announcement")).toHaveText("White moved from a2 to a3.")
    await expect(page.locator("#breakthrough-board button[tabindex='0']")).toHaveCount(1)
    await expect(page.locator("#square-a6")).toBeFocused()
    await page.keyboard.press("Control+Home")
    await expect(page.locator("#square-a1")).toBeFocused()
    await page.keyboard.press("Control+End")
    await expect(page.locator("#square-h8")).toBeFocused()
    await expect(page.locator("#move-1")).toContainText("a2")
    await expect(page.locator("#move-1")).toContainText("a3")
  } finally {
    await watcher.context.close()
    await black.context.close()
  }
})

test("resignation requires confirmation, restores focus, explains the result, and supports replay", async ({page}) => {
  const url = await createGame(page, "ai")
  await expect(page.locator("#share-link-panel")).toHaveCount(0)
  await page.locator("#resign-game-button").click()
  await expect(page.locator("#resign-dialog")).toBeVisible()
  await expect(page.locator("#keep-playing-button")).toBeFocused()
  await page.keyboard.press("Tab")
  await expect(page.locator("#confirm-resign-button")).toBeFocused()
  await page.keyboard.press("Tab")
  await expect(page.locator("#keep-playing-button")).toBeFocused()
  await page.keyboard.press("Escape")
  await expect(page.locator("#resign-dialog")).toBeHidden()
  await expect(page.locator("#resign-game-button")).toBeFocused()
  await expect(page.locator("#phase-value")).toHaveText("Your move")
  await page.locator("#resign-game-button").click()
  await page.locator("#confirm-resign-button").click()
  await expect(page.locator("#phase-value")).toHaveText("You lost")
  await expect(page.locator("#board-prompt")).toContainText("Black wins by resignation")
  await expect(page.locator("#resign-game-button")).toHaveCount(0)
  await expect(page.locator("#black-player")).toContainText("Winner")
  await page.getByRole("button", {name: "Play again", exact: true}).click()
  await expect(page).not.toHaveURL(url)
  await expect(page.locator("#phase-value")).toHaveText("Your move")
})

test("click or tap selects once and Escape clears the selection", async ({page}, testInfo) => {
  await createGame(page, "ai")
  const square = page.locator("#square-a7")
  if (testInfo.project.name === "mobile") await square.tap()
  else await square.click()
  await expect(square).toHaveAttribute("data-selected", "true")
  await square.focus()
  await page.keyboard.press("Escape")
  await expect(square).toHaveAttribute("data-selected", "false")
  await page.locator("#dismiss-guidance-button").click()
  await expect(page.locator("#match-guidance")).toHaveCount(0)
})

test("desktop dragging moves a pawn without a second click", async ({page, browser}, testInfo) => {
  test.skip(testInfo.project.name === "mobile", "Touch players use tap-to-move")
  const url = await createGame(page)
  const black = await joinGame(browser, url)
  try {
    await expect(page.locator("#breakthrough-board")).toHaveAttribute("data-can-drag", "true")
    const from = await page.locator("#square-a7").boundingBox()
    const to = await page.locator("#square-a6").boundingBox()
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2)
    await page.mouse.down()
    await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, {steps: 8})
    await page.mouse.up()
    await expect(page.locator("#square-a6")).toHaveAttribute("data-piece", "W")
    await expect(page.locator("#square-a7")).toHaveAttribute("data-piece", "empty")
  } finally {
    await black.context.close()
  }
})

test("representative states fit the viewport and pass automated accessibility checks", async ({page}, testInfo) => {
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  await createGame(page, "ai")
  const originalViewport = page.viewportSize()
  for (const width of [320, 768, originalViewport.width]) {
    await page.setViewportSize({width, height: originalViewport.height})
    await checkLayout(page)
  }
  await page.setViewportSize(originalViewport)
  await capture(page, testInfo, "playing-table")
  const activeScan = await new AxeBuilder({page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze()
  expect(activeScan.violations).toEqual([])
  await page.locator("#resign-game-button").click()
  await capture(page, testInfo, "resign-dialog")
  const dialogScan = await new AxeBuilder({page}).withTags(["wcag2a", "wcag2aa", "wcag21aa"]).analyze()
  expect(dialogScan.violations).toEqual([])
  await page.locator("#confirm-resign-button").click()
  await capture(page, testInfo, "match-result")
  expect(errors).toEqual([])
})


test("a breakthrough explains the win and both players accept a rematch with swapped colors", async ({page, browser}) => {
  const url = await createGame(page)
  const black = await joinGame(browser, url)
  try {
    const turns = [
      [page, "a7", "a6"], [black.page, "h2", "h3"],
      [page, "a6", "a5"], [black.page, "h3", "h4"],
      [page, "a5", "a4"], [black.page, "h4", "h5"],
      [page, "a4", "a3"], [black.page, "h5", "h6"],
      [page, "a3", "b2"], [black.page, "h6", "g7"],
      [page, "b2", "a1"],
    ]
    for (const [player, from, to] of turns) {
      await expect(player.locator("#breakthrough-board")).toHaveAttribute("data-can-drag", "true")
      await player.locator(`#square-${from}`).click()
      await expect(player.locator(`#square-${from}`)).toHaveAttribute("data-selected", "true")
      await player.locator(`#square-${to}`).click()
      await expect(player.locator(`#square-${from}`)).toHaveAttribute("data-piece", "empty")
    }
    await expect(page.locator("#phase-value")).toHaveText("You won")
    await expect(black.page.locator("#phase-value")).toHaveText("You lost")
    await expect(page.locator("#board-prompt")).toHaveText("White reached the back rank on a8.")
    await expect(page.locator("#square-a1")).toHaveAttribute("data-finish-square", "true")
    await page.getByRole("button", {name: "Request rematch", exact: true}).click()
    await expect(page.locator("#rematch-pending-indicator")).toBeVisible()
    await black.page.getByRole("button", {name: "Accept rematch", exact: true}).click()
    await expect(page).not.toHaveURL(url)
    await expect(black.page).not.toHaveURL(url)
    await expect(page.locator("#player-side-value")).toHaveAttribute("data-side", "black")
    await expect(black.page.locator("#player-side-value")).toHaveAttribute("data-side", "white")
  } finally {
    await black.context.close()
  }
})


test("a waiting game can be cancelled directly from the lobby", async ({page}) => {
  const url = await createGame(page)
  await expect(page.locator("#cancel-game-button")).toBeInViewport()
  await page.locator("#back-to-lobby").click()
  await expect(page.locator("#cancel-current-game-button")).toBeVisible()
  await page.locator("#cancel-current-game-button").click()
  await expect(page.locator("#home-info-banner")).toContainText("Waiting game cancelled")
  await expect(page.locator("#current-created-game")).toHaveCount(0)
  await page.locator("#create-ai-game-button").click()
  await expect(page).toHaveURL(/\/games\/[^/]+$/)
  expect(page.url()).not.toBe(url)
})


test("the lobby removes waiting-game cancellation as soon as an opponent joins", async ({page, browser}) => {
  const url = await createGame(page)
  await page.locator("#back-to-lobby").click()
  await expect(page.locator("#cancel-current-game-button")).toBeVisible()
  const opponent = await joinGame(browser, url)
  try {
    await expect(page.locator("#current-game-title")).toHaveText("You have a multiplayer game in progress")
    await expect(page.locator("#cancel-current-game-button")).toHaveCount(0)
    await page.locator("#create-ai-game-button").click()
    await expect(page).toHaveURL(/\/$/)
    await expect(page.locator("#new-game-notice")).toContainText("A new game wasn’t created")
  } finally {
    await opponent.context.close()
  }
})
