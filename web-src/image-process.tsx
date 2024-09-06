'use client'

import React, { useMemo, useRef, useState } from 'react'
import ReactCrop, { Crop, PixelCrop } from 'react-image-crop'
import 'react-image-crop/dist/ReactCrop.css'
import { saveAs } from 'file-saver'
import JSZip from 'jszip'

type ImageData = {
  file: File
  label: string
  offset: { x: number; y: number }
}

type SuiteData = {
  rotation: number
  crop: PixelCrop
}

const ImageUpload = ({ onUpload }: { onUpload: (images: ImageData[]) => void }) => {
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = (e.target as HTMLInputElement).files;
    if (files) {
      const newImages = Array.from(files).map(file => ({
        file,
        label: '',
        offset: { x: 0, y: 0 }
      }))
      onUpload(newImages)
    }
  }

  return (
    <div className="p-4 border rounded">
      <h2 className="text-2xl font-bold mb-4">Step 1: Load Images</h2>
      <input type="file" multiple onChange={handleFileChange} accept="image/*" className="mb-4" />
    </div>
  )
}

const ImageProcessing = ({ image, onComplete }: { image: ImageData, onComplete: (suiteData: SuiteData) => void }) => {
  const [rotation, setRotation] = useState(0)
  const [crop, setCrop] = useState<Crop | undefined>(undefined)

  const handleRotation = (angle: number) => {
    setRotation((prevRotation) => (prevRotation + angle) % 360)
  }

  const handleComplete = () => {
    if (crop == null) {
      alert("Crop needs to be set!")
      return;
    }
    onComplete({
      rotation,
      crop: crop as PixelCrop
    })
  }

  const cropImageRef = useRef<HTMLImageElement>(null)

  return (
    <div className="p-4 border rounded">
      <h2 className="text-2xl font-bold mb-4">Step 2: Process Image</h2>
      <div className="mb-4">
        <ReactCrop crop={crop} onChange={(c) => setCrop(c)}>
          <img
            ref={cropImageRef}
            src={useMemo(() => {
              return URL.createObjectURL(image.file)
            }, [image.file])}
            alt="Processing"
            style={{ transform: `rotate(${rotation}deg)`, maxWidth: 'none', width: 'auto', height: 'auto' }}
          />
        </ReactCrop>
      </div>
      <div className="mb-4">
        <button onClick={() => handleRotation(90)} className="bg-blue-500 text-white px-4 py-2 rounded mr-2">Rotate 90°</button>
        <button onClick={() => handleRotation(-90)} className="bg-blue-500 text-white px-4 py-2 rounded">Rotate -90°</button>
      </div>
      <button onClick={handleComplete} className="bg-green-500 text-white px-4 py-2 rounded">Next</button>
    </div>
  )
}

const ImageLabeling = ({ suite, image, firstImage, onComplete }: { suite: SuiteData, image: ImageData, firstImage: ImageData, onComplete: (labeledImage: ImageData) => void }) => {
  const [label, setLabel] = useState('')
  const [offset, setOffset] = useState({ x: 0, y: 0 })

  const handleOffsetChange = (e: React.ChangeEvent<HTMLInputElement>, axis: 'x' | 'y') => {
    setOffset(prevOffset => ({
      ...prevOffset,
      [axis]: parseInt((e.target as HTMLInputElement).value, 10)
    }))
  }

  const handleComplete = () => {
    onComplete({
      ...image,
      label,
      offset
    })
  }

  return (
    <div className="p-4 border rounded">
      <h2 className="text-2xl font-bold mb-4">Step 3: Label and Align Image</h2>
      <div className="mb-4 relative" style={{ position: 'relative' }}>
        <img
          src={useMemo(() => URL.createObjectURL(image.file), [image.file])}
          alt="Current Image"
          style={{
            transform: `rotate(${suite.rotation}deg)`
          }}
        />
        <img
          src={useMemo(() => URL.createObjectURL(firstImage.file), [firstImage.file])}
          alt="First Image Overlay"
          style={{
            position: 'absolute',
            left: `${offset.x}px`,
            top: `${offset.y}px`,
            opacity: '50%',
            transform: `rotate(${suite.rotation}deg)`,
          }}
        />
      </div>
      <div className="mb-4">
        <label className="block mb-2">Label:</label>
        <select
          value={label}
          onChange={(e) => setLabel((e.target as HTMLSelectElement).value)}
          className="border p-2 rounded"
        >
          <option value="">Select a label</option>
          <option value="diffuse">Diffuse</option>
          <option value="alpha">Alpha</option>
          <option value="light-left">Light Left</option>
          <option value="light-top">Light Top</option>
          <option value="light-right">Light Right</option>
          <option value="light-bottom">Light Bottom</option>
        </select>
      </div>
      <div className="mb-4">
        <label className="block mb-2">Offset X:</label>
        <input
          type="number"
          value={offset.x}
          onChange={(e) => handleOffsetChange(e, 'x')}
          className="border p-2 rounded"
        />
      </div>
      <div className="mb-4">
        <label className="block mb-2">Offset Y:</label>
        <input
          type="number"
          value={offset.y}
          onChange={(e) => handleOffsetChange(e, 'y')}
          className="border p-2 rounded"
        />
      </div>
      <button onClick={handleComplete} className="bg-green-500 text-white px-4 py-2 rounded">Next</button>
    </div>
  )
}

export default function ImageProcessingWorkflow() {
  const [images, setImages] = useState<ImageData[]>([])
  const [suite, setSuite] = useState<SuiteData | undefined>(undefined);
  const [currentImageIndex, setCurrentImageIndex] = useState(0)
  const [currentStep, setCurrentStep] = useState(1)

  const handleUpload = (newImages: ImageData[]) => {
    setImages(newImages)
    setCurrentStep(2)
  }

  const handleProcessingComplete = (suite: SuiteData) => {
    setSuite(suite)
    setCurrentStep(3)
  }

  const handleLabelingComplete = (labeledImage: ImageData) => {
    setImages(prevImages => {
      const newImages = [...prevImages]
      newImages[currentImageIndex] = labeledImage
      return newImages
    })
    if (images.map(image => image.label).find(label => label == labeledImage.label) != null) {
      alert(`The label ${labeledImage.label} is already set! Please use a different label`)
      return
    }
    if (currentImageIndex < images.length - 1) {
      setCurrentImageIndex(prevIndex => prevIndex + 1)
      setCurrentStep(3)
    } else {
      setCurrentStep(4)
    }
  }

  const generateGUID = () => {
    const guid = Math.random().toString(36).substring(2, 7)
    console.log(`New GUID generated ${guid}`)
    return guid
  }

  const processAndDownloadImages = async () => {
    console.log("button clicked")
    if (suite == null)
      return

    const zip = new JSZip()
    const guid = generateGUID()


    for (const image of images) {
      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')
      if (!ctx) continue

      const img = new Image()
      img.src = URL.createObjectURL(image.file)
      await new Promise(resolve => { img.onload = resolve })
      console.log("image loaded")

      // Set canvas size to image size
      canvas.width = img.width
      canvas.height = img.height

      // Apply rotation
      ctx.translate(canvas.width / 2, canvas.height / 2)
      ctx.rotate((suite.rotation * Math.PI) / 180)
      ctx.drawImage(img, -img.width / 2, -img.height / 2)
      ctx.setTransform(1, 0, 0, 1, 0, 0)

      // Apply crop
      if (suite.crop) {
        const croppedCanvas = document.createElement('canvas')
        const croppedCtx = croppedCanvas.getContext('2d')
        if (!croppedCtx) continue

        croppedCanvas.width = suite.crop.width
        croppedCanvas.height = suite.crop.height
        croppedCtx.drawImage(
          canvas,
          suite.crop.x + image.offset.x,
          suite.crop.y + image.offset.y,
          suite.crop.width,
          suite.crop.height,
          0,
          0,
          suite.crop.width,
          suite.crop.height
        )
        canvas.width = suite.crop.width
        canvas.height = suite.crop.height
        ctx.drawImage(croppedCanvas, 0, 0)
      }

      // // Apply offset
      // const offsetCanvas = document.createElement('canvas')
      // const offsetCtx = offsetCanvas.getContext('2d')
      // if (!offsetCtx) continue

      // offsetCanvas.width = canvas.width
      // offsetCanvas.height = canvas.height
      // offsetCtx.drawImage(canvas, image.offset.x, image.offset.y)

      console.log("image transformed")

      const blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve))
      if (blob) {
        zip.file(`${image.label}.png`, blob)
      }
      console.log("image zipped!")
    }

    zip.generateAsync({ type: 'blob' }).then(content => {
      saveAs(content, `${guid}.zip`)
    })
  }

  const renderCurrentStep = () => {
    switch (currentStep) {
      case 1:
        return <ImageUpload onUpload={handleUpload} />
      case 2:
        return images.length > 0 && (
          <ImageProcessing
            image={images[currentImageIndex]}
            onComplete={handleProcessingComplete}
          />
        )
      case 3:
        return images.length > 0 && (
          <ImageLabeling
            suite={suite!}
            image={images[currentImageIndex]}
            firstImage={images[0]}
            onComplete={handleLabelingComplete}
          />
        )
      case 4:
        return (
          <div className="p-4 border rounded">
            <h2 className="text-2xl font-bold mb-4">Step 4: Download Processed Images</h2>
            <button onClick={processAndDownloadImages} className="bg-green-500 text-white px-4 py-2 rounded">
              Download Processed Images
            </button>
          </div>
        )
      default:
        return null
    }
  }

  return (
    <div className="container mx-auto p-4">
      <h1 className="text-3xl font-bold mb-6">Image Processing Workflow</h1>
      {renderCurrentStep()}
    </div>
  )
}
