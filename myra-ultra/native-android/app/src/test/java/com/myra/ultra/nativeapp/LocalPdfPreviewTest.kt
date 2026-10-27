package com.myra.ultra.nativeapp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalPdfPreviewTest {
    @Test fun pageBitmapDimensionsStayWithinTheEdgeLimitAndKeepAspectRatio() {
        assertEquals(1_600 to 800, LocalPdfPreview.pageBitmapSize(3_200, 1_600))
        assertEquals(800 to 1_600, LocalPdfPreview.pageBitmapSize(800, 1_600))
        assertEquals(640 to 480, LocalPdfPreview.pageBitmapSize(640, 480))
    }

    @Test fun pageNavigationAcceptsOnlyIndexesInsideANonEmptyDocument() {
        assertEquals(0, LocalPdfPreview.pageIndexOrNull(0, 1))
        assertEquals(2, LocalPdfPreview.pageIndexOrNull(2, 3))
        assertNull(LocalPdfPreview.pageIndexOrNull(-1, 3))
        assertNull(LocalPdfPreview.pageIndexOrNull(3, 3))
        assertNull(LocalPdfPreview.pageIndexOrNull(0, 0))
        assertNull(LocalPdfPreview.pageIndexOrNull(0, -1))
    }

    @Test fun invalidPageDimensionsAreRejected() {
        assertNull(LocalPdfPreview.pageBitmapSize(0, 500))
        assertNull(LocalPdfPreview.pageBitmapSize(500, -1))
        assertNull(LocalPdfPreview.pageBitmapSize(500, 500, 0))
    }
}
