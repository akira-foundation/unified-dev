import Testing
@testable import Core

@Suite("File tab draft controls")
struct FileTabDraftControlsTests {
    private func controls(
        _ mode: FileTabMode, canEdit: Bool = true, hasDraft: Bool = true, isDirty: Bool = false,
        isSaving: Bool = false, changedOnDisk: Bool = false
    ) -> FileTabDraftControls {
        FileTabDraftControls(
            mode: mode, canEdit: canEdit, hasDraft: hasDraft, isDirty: isDirty,
            isSaving: isSaving, changedOnDisk: changedOnDisk
        )
    }

    @Test("an unsaved draft can be saved from Preview")
    func previewSaves() {
        #expect(controls(.preview, isDirty: true).canSave)
    }

    @Test("an unsaved draft can be saved from Source, where it is shown read only")
    func sourceSaves() {
        #expect(controls(.source, isDirty: true).canSave)
    }

    @Test("nothing is saved with no edits, while a save runs, or where editing is not allowed")
    func nothingToSave() {
        for mode in FileTabMode.allCases {
            #expect(!controls(mode).canSave)
            #expect(!controls(mode, isDirty: true, isSaving: true).canSave)
            #expect(!controls(mode, canEdit: false, isDirty: true).canSave)
        }
    }

    @Test("Preview keeps watching the disk while a draft is open, unsaved or not")
    func previewWatchesADraft() {
        #expect(controls(.preview, isDirty: true).watchesDisk)
        #expect(controls(.preview, isDirty: false).watchesDisk)
    }

    @Test("Preview with no draft leaves the disk to the page, which reloads itself")
    func previewWithoutDraft() {
        #expect(!controls(.preview, hasDraft: false).watchesDisk)
    }

    @Test("the editor modes watch the disk from the moment they open")
    func editorsWatch() {
        #expect(controls(.source, hasDraft: false).watchesDisk)
        #expect(controls(.edit, hasDraft: false).watchesDisk)
    }

    @Test("a change on disk is shown in every mode that holds a draft")
    func diskChangeShown() {
        for mode in FileTabMode.allCases {
            #expect(controls(mode, isDirty: true, changedOnDisk: true).showsDiskChange)
            #expect(!controls(mode, isDirty: true, changedOnDisk: false).showsDiskChange)
            #expect(!controls(mode, hasDraft: false, changedOnDisk: true).showsDiskChange)
        }
    }

    @Test("a tab that may not edit shows a change on disk but cannot write its draft over it")
    func readOnlyCannotOverwrite() {
        let readOnly = controls(.preview, canEdit: false, isDirty: true, changedOnDisk: true)
        #expect(readOnly.showsDiskChange)
        #expect(!readOnly.canOverwriteDisk)
        #expect(controls(.preview, isDirty: true, changedOnDisk: true).canOverwriteDisk)
        #expect(!controls(.edit, isDirty: true, isSaving: true, changedOnDisk: true).canOverwriteDisk)
        #expect(!controls(.edit, isDirty: true).canOverwriteDisk)
        #expect(!controls(.edit, hasDraft: false, isDirty: true, changedOnDisk: true).canOverwriteDisk)
    }

    @Test("a draft that is not held cannot be saved, whatever the dirty flag says")
    func noDraftNoSave() {
        #expect(!controls(.edit, hasDraft: false, isDirty: true).canSave)
    }
}
