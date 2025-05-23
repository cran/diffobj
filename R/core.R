# Copyright (C) 2021 Brodie Gaslam
#
# This file is part of "diffobj - Diffs for R Objects"
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Go to <https://www.r-project.org/Licenses/GPL-2> for a copy of the license.

#' @include s4.R

NULL


#' Generate a character representation of Shortest Edit Sequence
#'
#' @keywords internal
#' @seealso \code{\link{ses}}
#' @param x S4 object of class \code{MyersMbaSes}
#' @param ... unused
#' @return character vector

setMethod("as.character", "MyersMbaSes",
  function(x, ...) {
    dat <- as.data.frame(x)

    # Split our data into sections that have either deletes or inserts and get
    # rid of the matches

    dat <- dat[dat$type != "Match", ]
    d.s <- split(dat, dat$section)

    # For each section, compute whether we should display, change, insert,
    # delete, or both, and based on that append to the ses string

    ses_rng <- function(off, len)
      paste0(off, if(len > 1L) paste0(",", off + len - 1L))

    vapply(
      unname(d.s),
      function(d) {
        del <- sum(d$len[d$type == "Delete"])
        ins <- sum(d$len[d$type == "Insert"])
        if(del) {
          del.first <- which(d$type == "Delete")[[1L]]
          del.off <- d$off[del.first]
        }
        if(ins) {
          ins.first <- which(d$type == "Insert")[[1L]]
          ins.off <- d$off[ins.first]
        }
        if(del && ins) {
          paste0(ses_rng(del.off, del), "c", ses_rng(ins.off, ins))
        } else if (del) {
          paste0(ses_rng(del.off, del), "d", d$last.b[[1L]])
        } else if (ins) {
          paste0(d$last.a[[1L]], "a", ses_rng(ins.off, ins))
        } else {
          stop("Logic Error: unexpected edit type; contact maintainer.") # nocov
        }
      },
      character(1L)
) } )
# Used for mapping edit actions to numbers so we can use numeric matrices
# absolutely must be used to create the @type factor in the MBA object.
#
# DO NOT CHANGE LIGHTLY; SOME CODE MIGHT RELY ON THE UNDERLYING INTEGER POSITIONS

.edit.map <- c("Match", "Insert", "Delete")

setMethod("as.matrix", "MyersMbaSes",
  function(x, row.names=NULL, optional=FALSE, ...) {
    # map del/ins/match to numbers

    len <- length(x@type)
    matches <- x@type == "Match"
    section <- cumsum(matches + c(0L, head(matches, -1L)))

    # Track what the max offset observed so far for elements of the `a` string
    # so that if we have an insert command we can get the insert position in
    # `a`

    last.a <- c(
      if(len) 0L,
      head(
        cummax(
          ifelse(x@type != "Insert", x@offset + x@length, 1L)
        ) - 1L, -1L
    ) )
    # Do same thing with `b`, complicated because the matching entries are all
    # in terms of `a`

    last.b <- c(
      if(len) 0L,
      head(cumsum(ifelse(x@type != "Delete", x@length, 0L)), -1L)
    )
    cbind(
      type=as.integer(x@type), len=x@length, off=x@offset,
      section=section, last.a=last.a, last.b = last.b
    )
} )
setMethod("as.data.frame", "MyersMbaSes",
  function(x, row.names=NULL, optional=FALSE, ...) {
    len <- length(x@type)
    mod <- c("Insert", "Delete")
    dat <- data.frame(type=x@type, len=x@length, off=x@offset)
    matches <- dat$type == "Match"
    dat$section <- cumsum(matches + c(0L, head(matches, -1L)))

    # Track what the max offset observed so far for elements of the `a` string
    # so that if we have an insert command we can get the insert position in
    # `a`

    dat$last.a <- c(
      if(nrow(dat)) 0L,
      head(
        cummax(ifelse(dat$type != "Insert", dat$off + dat$len, 1L)) - 1L, -1L
    ) )

    # Do same thing with `b`, complicated because the matching entries are all
    # in terms of `a`

    dat$last.b <- c(
      if(nrow(dat)) 0L,
      head(cumsum(ifelse(dat$type != "Delete", dat$len, 0L)), -1L)
    )
    dat
} )
#' Shortest Edit Script
#'
#' Computes shortest edit script to convert \code{a} into \code{b} by removing
#' elements from \code{a} and adding elements from \code{b}.  Intended primarily
#' for debugging or for other applications that understand that particular
#' format.  See \href{http://www.gnu.org/software/diffutils/manual/diffutils.html#Detailed-Normal}{GNU diff docs}
#' for how to interpret the symbols.
#'
#' \code{ses} will be much faster than any of the
#' \code{\link[=diffPrint]{diff*}} methods, particularly for large inputs with
#' limited numbers of differences.
#'
#' NAs are treated as the string \dQuote{NA}.  Non-character inputs are coerced
#' to character.
#'
#' \code{ses_dat} provides a semi-processed \dQuote{machine-readable} version of
#' precursor data to \code{ses} that may be useful for those desiring to use the
#' raw diff data and not the printed output of \code{diffobj}, but do not wish
#' to manually parse the \code{ses} output.  Whether it is faster than
#' \code{ses} or not depends on the ratio of matching to non-matching values as
#' \code{ses_dat} includes matching values whereas \code{ses} does not.
#' \code{ses_dat} objects have a print method that makes it easy to interpret
#' the diff, but are actually data.frames.  You can see the underlying data by
#' using \code{as.data.frame}, removing the "ses_dat" class, etc..
#'
#' @export
#' @param a character
#' @param b character
#' @param extra TRUE (default) or FALSE, whether to also return the indices in
#'   \code{a} and \code{b} the diff values are taken from.  Set to FALSE for a
#'   small performance gain.
#' @inheritParams diffPrint
#' @param warn TRUE (default) or FALSE whether to warn if we hit
#'   \code{max.diffs}.
#' @return character shortest edit script, or a machine readable version of it
#'   as a \code{ses_dat} object, which is a \code{data.frame} with columns
#'   \code{op} (factor, values \dQuote{Match}, \dQuote{Insert}, or
#'   \dQuote{Delete}), \code{val} character corresponding to the value taken
#'   from either \code{a} or \code{b}, and if \code{extra} is TRUE, integer
#'   columns \code{id.a} and \code{id.b} corresponding to the indices in
#'   \code{a} or \code{b} that \code{val} was taken from.  See Details.
#' @examples
#' a <- letters[1:6]
#' b <- c('b', 'CC', 'DD', 'd', 'f')
#' ses(a, b)
#' (dat <- ses_dat(a, b))
#' str(dat)                 # data.frame with a print method
#'
#' ## use `ses_dat` output to construct a minimal diff
#' ## color with ANSI CSI SGR
#' diff <- dat[['val']]
#' del <- dat[['op']] == 'Delete'
#' ins <- dat[['op']] == 'Insert'
#' if(any(del))
#'   diff[del] <- paste0("\033[33m- ", diff[del], "\033[m")
#' if(any(ins))
#'   diff[ins] <- paste0("\033[34m+ ", diff[ins], "\033[m")
#' if(any(!ins & !del))
#'   diff[!ins & !del] <- paste0("  ", diff[!ins & !del])
#' writeLines(diff)
#'
#' ## We can recover `a` and `b` from the data
#' identical(subset(dat, op != 'Insert', val)[[1]], a)
#' identical(subset(dat, op != 'Delete', val)[[1]], b)

ses <- function(a, b, max.diffs=gdo("max.diffs"), warn=gdo("warn")) {
  args <- ses_prep(a=a, b=b, max.diffs=max.diffs, warn=warn)
  as.character(
    diff_myers(
      args[['a']], args[['b']], max.diffs=args[['max.diffs']],
      warn=args[['warn']]
  ) )
}
#' @export
#' @rdname ses

ses_dat <- function(
  a, b, extra=TRUE, max.diffs=gdo("max.diffs"), warn=gdo("warn")
) {
  args <- ses_prep(a=a, b=b, max.diffs=max.diffs, warn=warn)
  if(!is.TF(extra)) stop("Argument `extra` must be TRUE or FALSE.")
  mba <- diff_myers(
    args[['a']], args[['b']], max.diffs=args[['max.diffs']],
    warn=args[['warn']]
  )
  # reorder so that deletes are before (lack of foresight in setting factor
  # levels...) inserts in each section

  sec <- cumsum(mba@type == 'Match')
  o <- order(sec, c(1L,3L,2L)[as.integer(mba@type)])
  type <- mba@type[o]
  len <- mba@length[o]
  off <- mba@offset[o]

  # offsets are indices in `a` for 'Match' and 'Delete', and in `b` for insert
  # see `diff_myers` for details

  id <- rep(seq_along(type), len)
  type2 <- type[id]
  off2 <- off[id]
  id2 <- sequence(len) + off2 - 1L

  use.a <- type2 %in% c('Match', 'Delete')
  use.b <- !use.a
  values <- character(length(id))
  values[use.a] <- a[id2[use.a]]
  values[use.b] <- b[id2[use.b]]
  res <- if(extra) {
    id.a <- id.b <- rep(NA_integer_, length(values))
    id.a[use.a] <- id2[use.a]
    id.b[use.b] <- id2[use.b]

    data.frame(
      op=type2, val=values, id.a=id.a, id.b=id.b, stringsAsFactors=FALSE
    )
  } else {
    data.frame(op=type2, val=values, stringsAsFactors=FALSE)
  }
  structure(res, class=c('ses_dat', class(res)))
}
#' @export

print.ses_dat <- function(x, quote=FALSE, ...) {
  op <- x[['op']]
  diff <- matrix(
    "", 3, nrow(x),
    dimnames=list(c('D:', 'M:', 'I:'), character(nrow(x)))
  )
  d <- op == 'Delete'
  m <- op == 'Match'
  i <- op == 'Insert'
  diff[1, d] <- x[['val']][d]
  diff[2, m] <- x[['val']][m]
  diff[3, i] <- x[['val']][i]
  writeLines(
    sprintf(
      "\"ses_dat\" object (Match: %d, Delete: %d, Insert: %d):",
      sum(m), sum(d), sum(i)
  ) )
  print(diff, quote=quote, ...)
  invisible(x)
}

# Internal validation fun for ses_*

ses_prep <- function(a, b, max.diffs, warn) {
  if(!is.character(a)) {
    a <- try(as.character(a))
    if(inherits(a, "try-error"))
      stop("Argument `a` is not character and could not be coerced to such")
  }
  if(!is.character(b)) {
    b <- try(as.character(b))
    if(inherits(b, "try-error"))
      stop("Argument `b` is not character and could not be coerced to such")
  }
  if(is.numeric(max.diffs)) max.diffs <- as.integer(max.diffs)
  if(!is.int.1L(max.diffs)) stop("Argument `max.diffs` must be scalar integer.")
  if(!is.TF(warn)) stop("Argument `warn` must be TRUE or FALSE.")
  if(anyNA(a)) a[is.na(a)] <- "NA"
  if(anyNA(b)) b[is.na(b)] <- "NA"
  list(a=a, b=b, max.diffs=max.diffs, warn=warn)
}
#' Diff two character vectors
#'
#' Implementation of Myer's Diff algorithm with linear space refinement
#' originally implemented by Mike B. Allen as part of
#' \href{https://www.ioplex.com/~miallen/libmba/}{libmba}
#' version 0.9.1.  This implementation is a heavily modified version of the
#' original C code and is not compatible with the \code{libmba} library.
#' The C code is simplified by using fixed size arrays instead of variable
#' ones for tracking the longest reaching paths and for recording the shortest
#' edit scripts.  Additionally all error handling and memory allocation calls
#' have been moved to the internal R functions designed to handle those things.
#' A failover result is provided in the case where max diffs allowed is
#' exceeded.  Ability to provide custom comparison functions is removed.
#'
#' The result format indicates operations required to convert \code{a} into
#' \code{b} in a precursor format to the GNU diff shortest edit script.  The
#' operations are \dQuote{Match} (do nothing), \dQuote{Insert} (insert one or
#' more values of \code{b} into \code{a}), and \dQuote{Delete} (remove one or
#' more values from \code{a}).  The \code{length} slot dictates how
#' many values to advance along, insert into, or delete from \code{a}.  The
#' \code{offset} slot changes meaning depending on the operation.  For
#' \dQuote{Match} and \dQuote{Delete}, it is the starting index of that
#' operation in \code{a}.  For \dQuote{Insert}, it is the starting index in
#' \code{b} of the values to insert into \code{a}; the index in \code{a} to
#' insert at is implicit in previous operations.
#'
#' @keywords internal
#' @param a character
#' @param b character
#' @param max.diffs integer(1L) how many differences before giving up; set to
#'   -1 to allow as many as there are up to the maximum allowed (~INT_MAX/4).
#' @param warn TRUE or FALSE, whether to warn if we hit `max.diffs`.
#' @return MyersMbaSes object
#' @useDynLib diffobj, .registration=TRUE, .fixes="DIFFOBJ_"

diff_myers <- function(a, b, max.diffs=-1L, warn=FALSE) {
  stopifnot(
    is.character(a), is.character(b), all(!is.na(c(a, b))), is.int.1L(max.diffs),
    is.TF(warn)
  )
  a <- enc2utf8(a)
  b <- enc2utf8(b)
  res <- .Call(DIFFOBJ_diffobj, a, b, max.diffs)
  res <- setNames(res, c("type", "length", "offset", "diffs"))
  types <- .edit.map
  # silly that we have to generate a factor when we have the integer vector and
  # levels...  Two unncessary hashes.
  res$type <- factor(types[res$type], levels=types)
  res$offset <- res$offset + 1L  # C 0-indexing originally
  res.s4 <- try(do.call("new", c(list("MyersMbaSes", a=a, b=b), res)))
  if(inherits(res.s4, "try-error"))
    # nocov start
    stop(
      "Logic Error: unable to instantiate shortest edit script object; contact ",
      "maintainer."
    )
    # nocov end
  if(isTRUE(warn) && res$diffs < 0) {
    warning(
      "Exceeded `max.diffs`: ", abs(res$diffs), " vs ", max.diffs, " allowed. ",
      "Diff is probably suboptimal."
    )
  }
  res.s4
}
# Print Method for Shortest Edit Path
#
# Bare bones display of shortest edit path using GNU diff conventions
#
# @param object object to display
# @return character the shortest edit path character representation, invisibly
# @rdname diffobj_s4method_doc

#' @rdname diffobj_s4method_doc

setMethod("show", "MyersMbaSes",
  function(object) {
    res <- as.character(object)
    cat(res, sep="\n")
    invisible(res)
} )

#' Summary Method for Shortest Edit Path
#'
#' Displays the data required to generate the shortest edit path for comparison
#' between two strings.
#'
#' @export
#' @keywords internal
#' @param object the \code{diff_myers} object to display
#' @param with.match logical(1L) whether to show what text the edit command
#'   refers to
#' @param ... forwarded to the data frame print method used to actually display
#'   the data
#' @return whatever the data frame print method returns

setMethod("summary", "MyersMbaSes",
  function(object, with.match=FALSE, ...) {
    what <- vapply(
      seq_along(object@type),
      function(y) {
        t <- object@type[[y]]
        o <- object@offset[[y]]
        l <- object@length[[y]]
        vec <- if(t == "Insert") object@b else object@a
        paste0(vec[o:(o + l - 1L)], collapse="")
      },
      character(1L)
    )
    res <- data.frame(
      type=object@type, string=what, len=object@length, offset=object@offset,
      stringsAsFactors=FALSE
    )
    if(!with.match) res <- res[-2L]
    print(res, ...)
} )
# mode is display mode (sidebyside, etc.)
# diff.mode is whether we are doing the first pass line diff, or doing the
#   in-hunk or word-wrap versions
# warn is to allow us to suppress warnings after first hunk warning

char_diff <- function(x, y, context=-1L, etc, diff.mode, warn) {
  stopifnot(
    diff.mode %in% c("line", "hunk", "wrap"),
    isTRUE(warn) || identical(warn, FALSE)
  )
  max.diffs <- etc@max.diffs
  # probably shouldn't generate S4, but easier...
  diff <- diff_myers(x, y, max.diffs, warn=FALSE)

  hunks <- as.hunks(diff, etc=etc)
  hit.diffs.max <- FALSE
  if(diff@diffs < 0L) {
    hit.diffs.max <- TRUE
    diff@diffs <- -diff@diffs
    diff.msg <- c(
      line="overall", hunk="in-hunk word", wrap="atomic wrap-word"
    )
    if(warn)
      warning(
        "Exceeded diff limit during diff computation (",
        diff@diffs, " vs. ", max.diffs, " allowed); ",
        diff.msg[diff.mode], " diff is likely not optimal",
        call.=FALSE
      )
  }
  # used to be a `DiffDiffs` object, but too slow

  list(hunks=hunks, hit.diffs.max=hit.diffs.max)
}
# Compute the character representation of a hunk header

make_hh <- function(h.g, mode, tar.dat, cur.dat, ranges.orig) {
  h.ids <- vapply(h.g, "[[", integer(1L), "id")
  h.head <- vapply(h.g, "[[", logical(1L), "guide")

  # exclude header hunks from contributing to range, and adjust ranges for
  # possible fill lines added to the data

  h.ids.nh <- h.ids[!h.head]

  tar.rng <- find_rng(h.ids.nh, ranges.orig[1:2, , drop=FALSE], tar.dat$fill)
  tar.rng.f <- cumsum(!tar.dat$fill)[tar.rng]

  cur.rng <- find_rng(h.ids.nh, ranges.orig[3:4, , drop=FALSE], cur.dat$fill)
  cur.rng.f <- cumsum(!cur.dat$fill)[cur.rng]

  hh.a <- paste0(rng_as_chr(tar.rng.f))
  hh.b <- paste0(rng_as_chr(cur.rng.f))

  if(mode == "sidebyside") sprintf("@@ %s @@", c(hh.a, hh.b)) else {
    sprintf("@@ %s / %s @@", hh.a, hh.b)
  }
}
# Do not allow `useBytes=TRUE` if there are any matches with `useBytes=FALSE`
#
# Clean up word.ind to avoid issues where we have mixed UTF-8 and non
# UTF-8 strings in different hunks, and gregexpr is trying to optimize
# buy using useBytes=TRUE in ASCII only strings without knowing that in a
# different hunk there are UTF-8 strings

fix_word_ind <- function(x) {
  matches <- vapply(x, function(y) length(y) > 1L || y != -1L, logical(1L))
  useBytes <- vapply(x, function(y) isTRUE(attr(y, "useBytes")), logical(1L))
  if(!all(useBytes[matches])) x <- lapply(x, `attr<-`, "useBytes", NULL)
  x
}
# Variation on `char_diff` used for the overall diff where we don't need
# to worry about overhead from creating the `Diff` object

line_diff <- function(
  target, current, tar.capt, cur.capt, context, etc, warn=TRUE, strip=TRUE
) {
  if(!is.valid.guide.fun(etc@guides))
    # nocov start
    stop(
      "Logic Error: guides are not a valid guide function; contact maintainer"
    )
    # nocov end
  etc@guide.lines <-
    make_guides(target, tar.capt, current, cur.capt, etc@guides)

  # Need to remove new lines as the processed captures do that anyway and we
  # end up with mismatched lengths if we don't

  if(any(nzchar(tar.capt)))
    tar.capt <- split_new_line(tar.capt, sgr.supported=etc@sgr.supported)
  if(any(nzchar(cur.capt)))
    cur.capt <- split_new_line(cur.capt, sgr.supported=etc@sgr.supported)

  # Some debate as to whether we want to do this first, or last.  First has
  # many benefits so that everything is consistent, width calcs can work fine,
  # etc., but only issue is that user provided trim functions might not expect
  # the transformation of the data; this needs to be documented with the trim
  # docs.

  tar.capt.p <- tar.capt
  cur.capt.p <- cur.capt
  if(etc@convert.hz.white.space) {
    tar.capt.p <- strip_hz_control(
      tar.capt, stops=etc@tab.stops, sgr.supported=etc@sgr.supported
    )
    cur.capt.p <- strip_hz_control(
      cur.capt, stops=etc@tab.stops, sgr.supported=etc@sgr.supported
    )
  }
  # Remove whitespace and CSI SGR if warranted

  if(etc@strip.sgr) {
    if(has.style.1 <- any(crayon::has_style(tar.capt.p)))
      tar.capt.p <- crayon::strip_style(tar.capt.p)
    if(has.style.2 <- any(crayon::has_style(cur.capt.p)))
      cur.capt.p <- crayon::strip_style(cur.capt.p)
    if(has.style.1 || has.style.2)
      etc@warn(
        "`target` or `current` contained ANSI CSI SGR when rendered; these ",
        "were stripped.  Use `strip.sgr=FALSE` to preserve them in the diffs."
      )
  }
  # Apply trimming to remove row heads, etc, but only if something gets trimmed
  # from both elements

  tar.trim.ind <- apply_trim(target, tar.capt.p, etc@trim)
  tar.trim <- do.call(
    substr, list(tar.capt.p, tar.trim.ind[, 1L], tar.trim.ind[, 2L])
  )
  cur.trim.ind <- apply_trim(current, cur.capt.p, etc@trim)
  cur.trim <- do.call(
    substr, list(cur.capt.p, cur.trim.ind[, 1L], cur.trim.ind[, 2L])
  )
  if(identical(tar.trim, tar.capt.p) || identical(cur.trim, cur.capt.p)) {
    # didn't trim in both, so go back to original
    tar.trim <- tar.capt.p
    tar.trim.ind <- cbind(
      rep(1L, length(tar.capt.p)),
      nchar(tar.capt.p)
    )
    cur.trim <- cur.capt.p
    cur.trim.ind <- cbind(
      rep(1L, length(cur.capt.p)),
      nchar(cur.capt.p)
    )
  }
  tar.comp <- tar.trim
  cur.comp <- cur.trim

  if(etc@ignore.white.space) {
    tar.comp <- normalize_whitespace(tar.comp)
    cur.comp <- normalize_whitespace(cur.comp)
  }
  # Word diff is done in three steps: create an empty template vector structured
  # as the result of a call to `gregexpr` without matches, if dealing with
  # compliant atomic vectors in print mode, then update with the word diff
  # matches, finally, update with in-hunk word diffs for hunks that don't have
  # any existing word diffs:

  # Set up data lists with all relevant info; need to pass to diff_word so it
  # can be modified.
  # - orig: the very original string
  # - raw: the original captured text line by line, with strip_hz applied
  # - trim: as above, but with row meta data removed
  # - trim.ind: the indices used to re-insert `trim` into `raw`
  # - comp: the strings that will have the line diffs run on, these can be
  #   modified to force a particular outcome, e.g. by word_to_line_map
  # - eq: the portion of `trim` that is equal post word-diff
  # - fin: the final character string for display to user
  # - word.ind: for use by `regmatches<-` to re-insert colored words
  # - tok.rat: for use by `align_eq` when lining up lines within hunks

  tar.dat <- list(
    orig=tar.capt, raw=tar.capt.p, trim=tar.trim,
    trim.ind.start=tar.trim.ind[, 1L], trim.ind.end=tar.trim.ind[, 2L],
    comp=tar.comp, eq=tar.comp, fin=tar.capt.p,
    fill=logical(length(tar.capt.p)),
    word.ind=replicate(length(tar.capt.p), .word.diff.atom, simplify=FALSE),
    tok.rat=rep(1, length(tar.capt.p))
  )
  cur.dat <- list(
    orig=cur.capt, raw=cur.capt.p, trim=cur.trim,
    trim.ind.start=cur.trim.ind[, 1L], trim.ind.end=cur.trim.ind[, 2L],
    comp=cur.comp, eq=cur.comp, fin=cur.capt.p,
    fill=logical(length(cur.capt.p)),
    word.ind=replicate(length(cur.capt.p), .word.diff.atom, simplify=FALSE),
    tok.rat=rep(1, length(cur.capt.p))
  )
  # Word diffs in wrapped form is atomic; note this will potentially change
  # the length of the vectors.

  tar.wrap.diff <- integer(0L)
  cur.wrap.diff <- integer(0L)
  tar.dat.w <- tar.dat
  cur.dat.w <- cur.dat

  if(
    is.atomic(target) && is.atomic(current) &&
    is.null(dim(target)) && is.null(dim(current)) &&
    length(tar.rh <- which_atomic_cont(tar.capt.p, target)) &&
    length(cur.rh <- which_atomic_cont(cur.capt.p, current)) &&
    is.null(names(target)) && is.null(names(current)) &&
    etc@unwrap.atomic && etc@word.diff
  ) {
    # For historical compatibility we allow `diffChr` to get into this step if
    # the text format is right, even though it is arguable whether it should be
    # allowed or not.

    if(!all(diff(tar.rh) == 1L) || !all(diff(cur.rh)) == 1L){
      # nocov start
      stop("Logic Error, row headers must be sequential; contact maintainer.")
      # nocov end
    }
    # Only do this for the portion of the data that actually matches up with
    # the atomic row headers.

    diff.word <- diff_word2(
      tar.dat, cur.dat, tar.ind=tar.rh, cur.ind=cur.rh,
      diff.mode="wrap", warn=warn, etc=etc
    )
    warn <- !diff.word$hit.diffs.max
    tar.dat.w <- diff.word$tar.dat
    cur.dat.w <- diff.word$cur.dat

    # Mark the lines that were wrapped diffed; necessary b/c tar/cur.rh are
    # defined even if other conditions to get in this loop are not, and also
    # because the addition of the fill lines moves everything around
    # (effectively tar/cur.wrap.diff are the fill-offset versions of tar/cur.rh)

    tar.wrap.diff <- seq_along(tar.dat.w$fill)[!tar.dat.w$fill][tar.rh]
    cur.wrap.diff <- seq_along(cur.dat.w$fill)[!cur.dat.w$fill][cur.rh]
  }
  # Actual line diff

  diffs <- char_diff(
    tar.dat.w$comp, cur.dat.w$comp, etc=etc, diff.mode="line", warn=warn
  )
  warn <- !diffs$hit.diffs.max

  hunks.flat <- diffs$hunks

  # For each of those hunks, run the word diffs and store the results in the
  # word.diffs list; bad part here is that we keep overwriting the overall
  # diff data for each hunk, which might be slow

  tar.dat.ww <- tar.dat.w
  cur.dat.ww <- cur.dat.w

  if(etc@word.diff) {
    # Word diffs on hunks, excluding all values that have already been wrap
    # diffed as in tar.rh and cur.rh / tar.wrap.diff and cur.wrap.diff

    for(h.a in hunks.flat) {
      if(h.a$context) next
      h.a.ind <- c(h.a$A, h.a$B)
      h.a.tar.ind <- setdiff(h.a.ind[h.a.ind > 0], tar.wrap.diff)
      h.a.cur.ind <- setdiff(abs(h.a.ind[h.a.ind < 0]), cur.wrap.diff)
      h.a.w.d <- diff_word2(
        tar.dat.ww, cur.dat.ww, h.a.tar.ind, h.a.cur.ind, diff.mode="hunk",
        warn=warn, etc=etc
      )
      tar.dat.ww <- h.a.w.d[['tar.dat']]
      cur.dat.ww <- h.a.w.d[['cur.dat']]
      warn <- warn || !h.a.w.d[['hit.diffs.max']]
    }
    # Compute the token ratios

    tok_ratio_compute <- function(z) vapply(
      z,
      function(y)
        if(is.null(wc <- attr(y, "word.count"))) 1
        else max(0, (wc - length(y)) / wc),
      numeric(1L)
    )
    tar.dat.ww$tok.rat <- tok_ratio_compute(tar.dat.ww$word.ind)
    cur.dat.ww$tok.rat <- tok_ratio_compute(cur.dat.ww$word.ind)

    # Deal with mixed UTF/plain strings

    tar.dat.ww$word.ind <- fix_word_ind(tar.dat.ww$word.ind)
    cur.dat.ww$word.ind <- fix_word_ind(cur.dat.ww$word.ind)

    # Remove different words to make equal strings

    tar.dat.ww$eq <- with(tar.dat.ww, `regmatches<-`(trim, word.ind, value=""))
    cur.dat.ww$eq <- with(cur.dat.ww, `regmatches<-`(trim, word.ind, value=""))
  }
  # Instantiate result

  hunk.grps.raw <- group_hunks(
    hunks.flat, etc=etc, tar.capt=tar.dat.ww$raw, cur.capt=cur.dat.ww$raw
  )
  gutter.dat <- etc@gutter
  max.w <- etc@text.width

  # Recompute line limit accounting for banner len, needed for correct trim

  etc.group <- etc
  if(etc.group@line.limit[[1L]] >= 0L) {
    etc.group@line.limit <-
      pmax(integer(2L), etc@line.limit - banner_len(etc@mode))
  }
  # Trim hunks to the extent needed to make sure we fit in lines

  hunk.grps <-
    trim_hunks(hunk.grps.raw, etc.group, tar.dat.ww$raw, cur.dat.ww$raw)
  hunks.flat <- unlist(hunk.grps, recursive=FALSE)

  # Compact to width of widest element, so retrieve all char values; also
  # need to generate all the hunk headers b/c we need to use them in width
  # computation as well; under no circumstances are hunk headers allowed to
  # wrap as they are always assumed to take one line.
  #
  # Note: this used to be done after trimming / subbing, which is technically
  # better since we might have trimmed away long rows, but we need to do it
  # here so that we can can record the new text width in the outgoing object;
  # also, logic a bit circuitous b/c this was originally done elsewhere; might
  # be faster to use tar.dat and cur.dat directly

  chr.ind <- unlist(lapply(hunks.flat, "[", c("A", "B")))
  chr.dat <- get_dat_raw(chr.ind, tar.dat.ww$raw, cur.dat.ww$raw)
  chr.size <- integer(length(chr.dat))

  ranges <- vapply(
    hunks.flat, function(h.a) c(h.a$tar.rng.trim, h.a$cur.rng.trim),
    integer(4L)
  )
  # compute ranges excluding fill lines
  rng_non_fill <- function(rng, fill) {
    if(!rng[[1L]]) rng else {
      rng.seq <- seq(rng[[1L]], rng[[2L]], by=1L)
      seq.not.fill <- rng.seq[!rng.seq %in% fill]
      if(!length(seq.not.fill)) {
        integer(2L)
      } else {
        range(seq.not.fill)
  } } }
  ranges.orig <- vapply(
    hunks.flat, function(h.a) {
      with(
        h.a, c(
          rng_non_fill(tar.rng.sub, which(tar.dat.ww$fill)),
          rng_non_fill(cur.rng.sub, which(cur.dat.ww$fill))
      ) )
    },
    integer(4L)
  )
  # We need a version of ranges that adjust for the fill lines that are counted
  # in the ranges but don't represent actual lines of output.  This does mean
  # that adjusted ranges are not necessarily contiguous

  hunk.heads <-
    lapply(hunk.grps, make_hh, etc@mode, tar.dat.ww, cur.dat.ww, ranges.orig)
  h.h.chars <- nchar2(
    chr_trim(
      unlist(hunk.heads), etc@line.width, sgr.supported=etc@sgr.supported
    ),
    sgr.supported=etc@sgr.supported
  )
  chr.size <- nchar2(chr.dat, sgr.supported=etc@sgr.supported)
  max.col.w <- max(
    max(0L, chr.size, .min.width + gutter.dat@width), h.h.chars
  )
  max.w <- if(max.col.w < max.w) max.col.w else max.w

  # future calculations should assume narrower display

  etc@text.width <- max.w
  etc@line.width <- max.w + gutter.dat@width

  new(
    "Diff", diffs=hunk.grps, target=target, current=current,
    hit.diffs.max=!warn, tar.dat=tar.dat.ww, cur.dat=cur.dat.ww, etc=etc,
    hunk.heads=hunk.heads, trim.dat=attr(hunk.grps, 'meta')
  )
}
