numeric = require 'numeric'
StackBlur = require 'stackblur-canvas'
kdt = require 'kdt'

EPSILON = 4
ROTATION_BINS = 8
CELLS = 4
WINDOW = 16
N = 2

video = document.querySelector 'video'
recordCanvas = document.querySelector '#record'
canvas = document.querySelector '#main'

recordCtx = recordCanvas.getContext '2d'
ctx = canvas.getContext '2d'

grayscale = (image) ->
  for el, i in image.data by 4
    image.data[i] = image.data[i + 1] = image.data[i + 2] =
      Math.max image.data[i], image.data[i + 1], image.data[i + 2]
      #Math.round(image.data[i] * 0.2126 + image.data[i + 1] * 0.7152 + image.data[i + 2] * 0.0772)
  return image

class GaussianPyramid
  constructor: (imageData) ->
    width = imageData.width
    height = imageData.height

    # Copy image data
    data = new Uint8ClampedArray(imageData.data.length)
    data.set imageData.data
    @data = new ImageData(data, width, height)

    # Make a blurred copy
    blurred = new Uint8ClampedArray(imageData.data.length)
    blurred.set data
    @blurred = new ImageData(blurred, width, height)
    StackBlur.imageDataRGBA @blurred, 0, 0, width, height, 1

    difference = new Uint8ClampedArray(imageData.data.length)
    for el, i in difference
      if i % 4 is 3
        difference[i] = 255
      else
        difference[i] = Math.abs (@blurred.data[i] - @data.data[i])
    @difference = new ImageData(difference, width, height)

    grayscale @difference

    # Subsample
    if width > 50 and height > 50
      newWidth = Math.floor imageData.width / 2
      newHeight = Math.floor imageData.height / 2
      subsampling = new Uint8ClampedArray(newWidth * newHeight * 4)
      for row in [0...newHeight]
        rowOffset = row * imageData.width * 2
        for col in [0...newWidth]
          for i in [0...4]
            subsampling[(row * newWidth + col) * 4 + i] = @blurred.data[(rowOffset + col * 2) * 4 + i]

      @next = new GaussianPyramid new ImageData(subsampling, newWidth, newHeight)
    else
      @next = null

    if @next?
      @next.prev = @

    @gradientCache = new Float64Array @data.data.length / 2

  gradient: (x, y) ->
    if @gradientCache[(y * @data.width + x) * 2] isnt 0
      return {
        theta: @gradientCache[(y * @data.width + x) * 2]
        r: @gradientCache[(y * @data.width + x) * 2 + 1]
      }

    unless 0 < x < @data.width and 0 < y < @data.height
      return {theta: 0, r: 0}

    index = (y * @data.width + x) * 4

    # Horizontal gradients
    horizontalGradients = []
    for j in [0..3]
      horizontalGradients[j] = (@data.data[index + 4] ? 0) - (@data.data[index - 4] ? 0)

    # Vertical gradients
    verticalGradients = []
    for j in [0..3]
      verticalGradients[j] = (@data.data[index + 4 * @data.width] ? 0) - (@data.data[index - 4 * @data.width] ? 0)

    gradientMagnitudes = horizontalGradients.map (x, i) -> x ** 2 + verticalGradients[i] ** 2

    best = null; max = -Infinity
    for el, j in gradientMagnitudes
      if el > max
        best = j; max = el

    theta = Math.atan2 verticalGradients[best], horizontalGradients[best]
    r = Math.sqrt max

    if theta < 0
      theta += Math.PI

    @gradientCache[(y * @data.width + x) * 2] = theta
    @gradientCache[(y * @data.width + x) * 2 + 1] = r

    return {theta, r}

  getMaximumGradients: (x, y) ->
    x -= WINDOW / 2
    y -= WINDOW / 2
    width = height = WINDOW

    votes = new Float64Array ROTATION_BINS
    for row in [y...y + height]
      for col in [x...x + width]
        gradient = @gradient row, col
        bin = Math.floor(ROTATION_BINS * gradient.theta / (Math.PI))
        votes[bin] += gradient.r

    best = null; max = -Infinity
    for el, i in votes
      if el > max
        best = i; max = el

    best = []
    for el, i in votes
      if el / max > 0.8
        best.push i

    return best

  # Sift descriptor using 4 8-bin normalized orientation histograms
  getSiftDescriptor: (angle, x, y) ->
    x -= WINDOW / 2; y -= WINDOW / 2
    descriptor = new Float64Array CELLS * CELLS * ROTATION_BINS
    j = 0; total = 0
    for row in [0...WINDOW]
      for col in [0...WINDOW]
        gradient = @gradient y + row, x + col
        bin = (Math.floor(ROTATION_BINS * gradient.theta / (Math.PI)) - angle) %% ROTATION_BINS
        descriptor[(Math.floor(row * CELLS / WINDOW) * CELLS + Math.floor(col * CELLS / WINDOW)) * ROTATION_BINS + bin] += gradient.r

    for el, i in descriptor
      total += el ** 2
    total = Math.sqrt total
    for el, i in descriptor
      descriptor[i] /= total

    return descriptor

  # Get local maxima
  getFeatures: ->
    maxima = {}
    for el, i in @difference.data by 4
      # Eight surrounding pixels
      surroundingPixels = [
        @difference.data[i - @difference.width * 4  - 4]
        @difference.data[i - @difference.width * 4]
        @difference.data[i - @difference.width * 4 + 4]
        @difference.data[i + @difference.width * 4 - 4]
        @difference.data[i + @difference.width * 4]
        @difference.data[i + @difference.width * 4 + 4]
        @difference.data[i - 4]
        @difference.data[i + 4]
      ]

      maximum = true
      for pixel in surroundingPixels
        if el - pixel < EPSILON
          maximum = false

      if maximum
        maxima[(i - i % 4) / 4] = true

    coordinates = []
    for key, val of maxima
      key = Number key
      coordinates.push {
        x: key % @difference.width
        y: (key - key % @difference.width) / @difference.width
      }

    return coordinates

navigator.webkitGetUserMedia {video: true}, ((stream) ->
  video.src = window.URL.createObjectURL stream
  #document.querySelector('button').addEventListener 'click', ->

  window.tree = tree = kdt.createKdTree [], getDistance = ((a, b) ->
    distance = 0
    for el, i in a
      distance += (el - b[i]) ** 2
    return distance
  ), [0...CELLS * CELLS * ROTATION_BINS]
  done = false

  originalData = null

  all = []
  tick = ->
    recordCtx.drawImage video, 0, 0, recordCanvas.width, recordCanvas.height
    image = recordCtx.getImageData(0, 0, recordCanvas.width, recordCanvas.height)

    ctx.clearRect 0, 0, canvas.width, canvas.height

    if done
      ctx.putImageData originalData, 500, 0

    for el, i in image.data by 4
      col = (i / 4) % image.width
      if col < image.width / 2
        for j in [0...4]
          swap = image.data[i + j]
          image.data[i + j] = image.data[i + j + (image.width - 2 * col) * 4]
          image.data[i + j + (image.width - 2 * col) * 4] = swap

    pyramid = base = new GaussianPyramid image
    leftOffset = 0
    scale = baseScale = 1
    ctx.putImageData pyramid.data, 0, 0
    for [1..3]
      pyramid = pyramid.next; scale *= 2

    until pyramid is null
      for el, i in pyramid.getFeatures()
        angles = pyramid.prev.prev.getMaximumGradients el.x * 4, el.y * 4
        for angle in angles
          descriptor = pyramid.prev.prev.getSiftDescriptor angle, el.x * 4, el.y * 4
          shouldFinish = false

          if done
            nearest = tree.nearest(descriptor, 2)
            if nearest[1][1] / nearest[0][1] < 0.8
              ctx.strokeStyle = '#0F0'
              ctx.beginPath()
              ctx.moveTo el.x * scale, el.y * scale
              ctx.lineTo nearest[1][0].x + 500, nearest[1][0].y
              ctx.stroke()
          else
            shouldFinish = true
            descriptor.x = el.x * scale
            descriptor.y = el.y * scale
            tree.insert descriptor
            all.push descriptor

          ctx.save()
          ctx.translate el.x * scale, el.y * scale
          ctx.rotate angle * Math.PI / ROTATION_BINS
          ctx.strokeStyle = '#00F'
          ctx.strokeRect -1, -scale/2, 1, scale
          ctx.strokeStyle = '#F00'
          ctx.strokeRect -scale/2, -scale/2, scale, scale
          ctx.restore()
          ctx.save()
          ctx.translate el.x * scale, el.y * scale
          ctx.strokeStyle = '#F00'
          ctx.strokeRect -1.5 * scale, -1.5 * scale, 3 * scale, 3 * scale
          ctx.restore()

      scale *= 2

      pyramid = pyramid.next

    unless done
      originalData = ctx.getImageData 0, 0, 500, 500

    if shouldFinish
      done = true
    setTimeout tick, 0

  setTimeout tick, 500
), (->)

