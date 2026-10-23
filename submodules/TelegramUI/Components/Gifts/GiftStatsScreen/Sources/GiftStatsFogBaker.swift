import Foundation
import UIKit

/// Bakes the fogged last row of the closed log off the main thread and caches it. The morph gets an image view that is filled
/// when the bake finishes (the row is not visible until about a third into the morph); it bakes on main only as a fallback.
final class GiftStatsFogBaker {
    /// `revision` changes when the row's model image arrives.
    struct Source {
        let component: GiftStatsRecentSalesComponent
        let revision: Int
        let size: CGSize

        func isSame(as other: Source) -> Bool {
            return self.component == other.component && self.revision == other.revision && self.size == other.size
        }
    }

    private final class Job {
        let source: Source
        let generation: Int
        var pictures: [UIImageView] = []

        init(source: Source, generation: Int) {
            self.source = source
            self.generation = generation
        }
    }

    private var ready: (source: Source, generation: Int, image: UIImage)?
    private var jobs: [Job] = []
    private var generation = 0

    func image(for source: Source) -> UIImage? {
        if let ready = self.ready, ready.source.isSame(as: source) {
            return ready.image
        }
        return nil
    }

    func isMade(_ source: Source) -> Bool {
        return self.image(for: source) != nil || self.job(for: source) != nil
    }

    func start(_ source: Source, flat: UIImage) {
        guard !self.isMade(source) else {
            return
        }
        self.generation += 1
        let job = Job(source: source, generation: self.generation)
        self.jobs.append(job)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = GiftStatsFogBake.bake(flat)
            DispatchQueue.main.async {
                self?.finished(job, image: image)
            }
        }
    }

    /// Filled when the bake finishes; if it is still empty after `seconds`, bakes `flat` synchronously.
    func picture(for source: Source, flat: UIImage, within seconds: Double) -> UIImageView {
        let picture = UIImageView()
        picture.frame = CGRect(origin: .zero, size: source.size)
        if let image = self.image(for: source) {
            picture.image = image
            return picture
        }
        let job = self.job(for: source)
        job?.pictures.append(picture)
        let generation = job?.generation ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak picture] in
            guard let self, let picture, picture.image == nil, let image = GiftStatsFogBake.bake(flat) else {
                return
            }
            picture.image = image
            self.store(source, generation: generation, image: image)
        }
        return picture
    }

    func imageNow(for source: Source, flat: () -> UIImage?) -> UIImage? {
        if let image = self.image(for: source) {
            return image
        }
        guard let flat = flat(), let image = GiftStatsFogBake.bake(flat) else {
            return nil
        }
        self.generation += 1
        self.store(source, generation: self.generation, image: image)
        return image
    }

    private func job(for source: Source) -> Job? {
        return self.jobs.first(where: { $0.source.isSame(as: source) })
    }

    private func finished(_ job: Job, image: UIImage?) {
        self.jobs.removeAll(where: { $0 === job })
        guard let image else {
            return
        }
        for picture in job.pictures where picture.image == nil {
            picture.image = image
        }
        job.pictures = []
        self.store(job.source, generation: job.generation, image: image)
    }

    private func store(_ source: Source, generation: Int, image: UIImage) {
        if let ready = self.ready, ready.generation > generation {
            return
        }
        self.ready = (source, generation, image)
    }
}
