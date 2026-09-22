// Pure local ranking for the Command Center action catalog.

function normalizeQuery(query) {
  if (typeof query !== "string")
    return ""
  return query.toLowerCase().trim().replace(/\s+/g, " ")
}

function queryTerms(query) {
  var normalized = normalizeQuery(query)
  return normalized === "" ? [] : normalized.split(" ")
}

function normalizedText(value) {
  return typeof value === "string" ? value.toLowerCase() : ""
}

function words(value) {
  var text = normalizedText(value)
  return text.split(/[^a-z0-9]+/).filter(function(word) { return word.length > 0 })
}

function nameMatches(action, term) {
  return normalizedText(action.name).indexOf(term) !== -1
}

function keywordOrCategoryMatches(action, term) {
  var category = normalizedText(action.category)
  if (category === term || category.indexOf(term) === 0)
    return true
  var keywords = Array.isArray(action.keywords) ? action.keywords : []
  for (var index = 0; index < keywords.length; index++) {
    var keyword = normalizedText(keywords[index])
    if (keyword === term || keyword.indexOf(term) === 0)
      return true
  }
  return false
}

function descriptionMatches(action, term) {
  var descriptionWords = words(action.description)
  for (var index = 0; index < descriptionWords.length; index++) {
    if (descriptionWords[index].indexOf(term) === 0)
      return true
  }
  return false
}

function matchesTerm(action, term) {
  return nameMatches(action, term)
    || keywordOrCategoryMatches(action, term)
    || descriptionMatches(action, term)
}

function matchesAllTerms(action, terms) {
  for (var index = 0; index < terms.length; index++) {
    if (!matchesTerm(action, terms[index]))
      return false
  }
  return true
}

// Lower numbers rank first. The whole query receives the strongest name tiers;
// multi-term queries then use the weakest field tier among their terms.
function rankAction(action, normalizedQuery, terms) {
  var name = normalizedText(action.name)
  if (name === normalizedQuery)
    return 0
  if (normalizedQuery !== "" && name.indexOf(normalizedQuery) === 0)
    return 1
  if (normalizedQuery !== "" && name.indexOf(normalizedQuery) !== -1)
    return 2

  var worstTermTier = 0
  for (var index = 0; index < terms.length; index++) {
    var term = terms[index]
    var tier
    if (name.indexOf(term) === 0)
      tier = 1
    else if (name.indexOf(term) !== -1)
      tier = 2
    else if (keywordOrCategoryMatches(action, term))
      tier = 3
    else
      tier = 4
    if (tier > worstTermTier)
      worstTermTier = tier
  }
  return worstTermTier
}

function search(actions, query) {
  var catalog = Array.isArray(actions) ? actions : []
  var normalizedQuery = normalizeQuery(query)
  var terms = queryTerms(query)
  var matches = []

  for (var index = 0; index < catalog.length; index++) {
    var action = catalog[index]
    if (!action || typeof action !== "object")
      continue
    if (terms.length === 0 || matchesAllTerms(action, terms)) {
      matches.push({ action: action, rank: terms.length === 0 ? 0 : rankAction(action, normalizedQuery, terms), order: index })
    }
  }

  matches.sort(function(left, right) {
    return left.rank - right.rank || left.order - right.order
  })
  return matches.map(function(match) { return match.action })
}
